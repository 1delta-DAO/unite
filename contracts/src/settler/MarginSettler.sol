// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {UniERC20} from "@1inch/solidity-utils/contracts/libraries/UniERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {IPreInteraction} from "@1inch/lo/interfaces/IPreInteraction.sol";
import {IPostInteraction} from "@1inch/lo/interfaces/IPostInteraction.sol";
import {ITakerInteraction} from "@1inch/lo/interfaces/ITakerInteraction.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {ContractSigner} from "../signer/ContractSigner.sol";
import "../Errors.sol";
import {ComposerCommands} from "../composer/lib/enums/DeltaEnums.sol";
import {Composer} from "../composer/Composer.sol";
import {UniversalFlashLoan} from "../composer/flashLoan/UniversalFlashLoan.sol";

contract MarginSettler is
    IPreInteraction,
    IPostInteraction,
    ITakerInteraction,
    ContractSigner,
    Composer,
    UniversalFlashLoan
{
    using AddressLib for Address;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    using Math for uint256;
    using MakerTraitsLib for MakerTraits;

    address private immutable _LIMIT_ORDER_PROTOCOL;
    address private immutable _WETH;

    constructor(address limitOrderProtocol, address weth) {
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
        _lendingParser(user, makingAmount, takingAmount, extraData);
    }

    function _lendingParser(
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

    /// @notice Post-interaction: Handle any cleanup after all transfers
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
        // TODO
    }

    /// @notice Taker interaction: Handle intermediate logic between transfers
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
        // TODO
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
        return
            IOrderMixin(_LIMIT_ORDER_PROTOCOL).fillContractOrderArgs(
                order,
                signature,
                amount,
                takerTraits,
                args
            );
    }
}
