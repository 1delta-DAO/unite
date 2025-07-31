// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {UniERC20} from "@1inch/solidity-utils/contracts/libraries/UniERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {IPreInteraction} from "@1inch/lo/interfaces/IPreInteraction.sol";
import {IPostInteraction} from "@1inch/lo/interfaces/IPostInteraction.sol";
import {ITakerInteraction} from "@1inch/lo/interfaces/ITakerInteraction.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {ContractSigner} from "../signer/ContractSigner.sol";
import "../Errors.sol";
import {ComposerCommands} from "../composer/lib/enums/DeltaEnums.sol";
import {Composer} from "../composer/Composer.sol";
import {UniversalFlashLoan} from "../composer/flashLoan/UniversalFlashLoan.sol";
import {ExternalCall} from "../composer/externalCall/ExternalCall.sol";

contract MarginSettler is
    IPostInteraction,
    ITakerInteraction,
    IPreInteraction,
    ContractSigner,
    Composer,
    UniversalFlashLoan,
    ExternalCall,
    EIP712
{
    using AddressLib for Address;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    using Math for uint256;
    using MakerTraitsLib for MakerTraits;
    using TakerTraitsLib for TakerTraits;

    address private immutable _LIMIT_ORDER_PROTOCOL;
    address private immutable _WETH;

    string private constant _NAME = "1DeltaMarginSettler";
    string private constant _VERSION = "1";

    constructor(
        address limitOrderProtocol,
        address weth
    ) EIP712(_NAME, _VERSION) {
        _LIMIT_ORDER_PROTOCOL = limitOrderProtocol;
        _WETH = weth;
    }

    modifier onlyLimitOrderProtocol() {
        if (msg.sender != _LIMIT_ORDER_PROTOCOL)
            revert OnlyLimitOrderProtocol();
        _;
    }

    function preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external override onlyLimitOrderProtocol {
        address user = order.receiver.get();
        // The lending operations map taker and maker amount as makerAmount: inputAmount, takerAmount: outputAmount
        _composer(user, takingAmount, makingAmount, extraData);
    }

    function _composer(
        address callerAddress,
        uint256 depositAmount,
        uint256 borrowAmount,
        bytes calldata lendingOps
    ) internal {
        uint256 length;
        uint256 maxIndex;
        uint256 currentOffset;
        assembly {
            length := calldataload(add(lendingOps.offset, 0x20))
            maxIndex := add(length, lendingOps.offset)
            currentOffset := add(lendingOps.offset, 0x40)
        }

        while (true) {
            uint256 operation;
            // fetch op metadata
            assembly {
                operation := shr(248, calldataload(currentOffset)) // last byte
                // we increment the current offset to skip the operation
                currentOffset := add(1, currentOffset)
            }
            if (operation == ComposerCommands.LENDING) {
                currentOffset = _lendingOperations(
                    callerAddress,
                    currentOffset,
                    depositAmount,
                    borrowAmount
                );
            } else if (operation == ComposerCommands.TRANSFERS) {
                currentOffset = _transfers(
                    currentOffset,
                    callerAddress,
                    depositAmount
                );
            } else if (operation == ComposerCommands.PERMIT) {
                currentOffset = _permit(
                    currentOffset,
                    callerAddress,
                    depositAmount
                );
            } else if (operation == ComposerCommands.FLASH_LOAN) {
                currentOffset = _universalFlashLoan(
                    currentOffset,
                    callerAddress,
                    borrowAmount
                );
            } else {
                _invalidOperation();
            }
            // break if we skipped over the calldata
            if (currentOffset >= maxIndex) break;
        }
        // revert if some excess is left
        if (currentOffset > maxIndex) revert InvalidCalldata();
    }

    function takerInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external override onlyLimitOrderProtocol {
        address user = order.receiver.get();
        // The lending operations map taker and maker amount as makerAmount: inputAmount, takerAmount: outputAmount
        _composer(user, takingAmount, makingAmount, extraData);
    }

    function postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external override onlyLimitOrderProtocol {
        address user = order.receiver.get();
        // The lending operations map taker and maker amount as makerAmount: inputAmount, takerAmount: outputAmount
        _composer(user, takingAmount, makingAmount, extraData);
    }

    function takeOrder(
        IOrderMixin.Order calldata order,
        bytes calldata signature,
        uint256 amount,
        TakerTraits takerTraits,
        bytes calldata args
    )
        external
        returns (uint256 makingAmount, uint256 takingAmount, bytes32 orderHash)
    {
        // extract extension
        (, bytes memory extension, ) = _parseArgs(takerTraits, args);
        if (extension.length < 65) {
            revert InvalidExtensionLength();
        }

        // last 65 bytes of the extension is the typedHash signature of the extension
        bytes memory extensionSignature = new bytes(65);
        assembly {
            mcopy(
                add(extensionSignature, 0x20),
                sub(add(mload(extension), add(extension, 0x20)), 65),
                65
            )
        }

        bytes32 extensionHash = _hashTypedDataV4(keccak256(extension));
        // recover the signer of the extension
        address signer = _recoverSigner(extensionHash, extensionSignature);

        return
            IOrderMixin(_LIMIT_ORDER_PROTOCOL).fillContractOrderArgs(
                order,
                abi.encodePacked(signature, signer), // append the signer of the extension to the signature
                amount,
                takerTraits,
                args
            );
    }

    /**
     * @notice Processes the taker interaction arguments.
     * @param takerTraits The taker preferences for the order.
     * @param args The taker interaction arguments.
     * @return target The address to which the order is filled.
     * @return extension The extension calldata of the order.
     * @return interaction The interaction calldata.
     */
    function _parseArgs(
        TakerTraits takerTraits,
        bytes calldata args
    )
        private
        view
        returns (
            address target,
            bytes calldata extension,
            bytes calldata interaction
        )
    {
        if (takerTraits.argsHasTarget()) {
            target = address(bytes20(args));
            args = args[20:];
        } else {
            target = msg.sender;
        }

        uint256 extensionLength = takerTraits.argsExtensionLength();
        if (extensionLength > 0) {
            extension = args[:extensionLength];
            args = args[extensionLength:];
        } else {
            extension = msg.data[:0];
        }

        uint256 interactionLength = takerTraits.argsInteractionLength();
        if (interactionLength > 0) {
            interaction = args[:interactionLength];
        } else {
            interaction = msg.data[:0];
        }
    }
}
