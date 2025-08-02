// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {UniERC20} from "@1inch/solidity-utils/contracts/libraries/UniERC20.sol";
import {ECDSA} from "@1inch/solidity-utils/contracts/libraries/ECDSA.sol";
import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {IPreInteraction} from "@1inch/lo/interfaces/IPreInteraction.sol";
import {IPostInteraction} from "@1inch/lo/interfaces/IPostInteraction.sol";
import {ITakerInteraction} from "@1inch/lo/interfaces/ITakerInteraction.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {ExtensionLib} from "@1inch/lo/libraries/ExtensionLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {ContractSigner} from "../signer/ContractSigner.sol";

import {ComposerCommands} from "../composer/lib/enums/DeltaEnums.sol";
import {Lending} from "../composer/lending/Lending.sol";
import {UniversalFlashLoan} from "../composer/flashLoan/UniversalFlashLoan.sol";
import {MorphoFlashLoanSimple} from "../composer/flashLoan/MorphoSimple.sol";
import {ExternalCall} from "../composer/externalCall/ExternalCall.sol";
import {Transfers} from "../composer/transfers/Transfers.sol";
import {Permits} from "../composer/permit/Permits.sol";
import "../Errors.sol";
import {console} from "forge-std/console.sol";

contract MarginSettler is
    IPostInteraction,
    ITakerInteraction,
    IPreInteraction,
    ContractSigner,
    Lending,
    MorphoFlashLoanSimple,
    UniversalFlashLoan,
    ExternalCall,
    Transfers,
    Permits,
    EIP712
{
    using AddressLib for Address;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    using Math for uint256;
    using MakerTraitsLib for MakerTraits;
    using TakerTraitsLib for TakerTraits;

    address private immutable _LIMIT_ORDER_PROTOCOL;

    string private constant _NAME = "1DeltaMarginSettler";
    string private constant _VERSION = "1";

    constructor(address limitOrderProtocol) EIP712(_NAME, _VERSION) {
        _LIMIT_ORDER_PROTOCOL = limitOrderProtocol;
    }

    modifier onlyLimitOrderProtocol() {
        if (msg.sender != _LIMIT_ORDER_PROTOCOL)
            revert OnlyLimitOrderProtocol();
        _;
    }

    function hashExtension(
        bytes memory extension
    ) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(extension));
    }

    /// @dev The typehash of the order struct.
    bytes32 internal constant _LIMIT_ORDER_TYPEHASH =
        keccak256(
            "Order("
            "uint256 salt,"
            "address maker,"
            "address receiver,"
            "address makerAsset,"
            "address takerAsset,"
            "uint256 makingAmount,"
            "uint256 takingAmount,"
            "uint256 makerTraits"
            ")"
        );
    uint256 internal constant _ORDER_STRUCT_SIZE = 0x100;
    uint256 internal constant _DATA_HASH_SIZE = 0x120;

    bytes32 private constant TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    function _buildDomainSeparator1inch() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TYPE_HASH,
                    keccak256(bytes("1inch Aggregation Router")),
                    keccak256(bytes("6")),
                    block.chainid,
                    _LIMIT_ORDER_PROTOCOL
                )
            );
    }

    function hashOrder(
        IOrderMixin.Order calldata order
    ) external view returns (bytes32 result) {
        bytes32 domainSeparator = _buildDomainSeparator1inch();
        bytes32 typehash = _LIMIT_ORDER_TYPEHASH;
        assembly ("memory-safe") {
            // solhint-disable-line no-inline-assembly
            let ptr := mload(0x40)

            // keccak256(abi.encode(_LIMIT_ORDER_TYPEHASH, order));
            mstore(ptr, typehash)
            calldatacopy(add(ptr, 0x20), order, _ORDER_STRUCT_SIZE)
            result := keccak256(ptr, _DATA_HASH_SIZE)
        }
        result = ECDSA.toTypedDataHash(domainSeparator, result);
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
        // usafe: the receiver cannot be the user here, the user data should be extracted from the order or extension data (via signer)
        address user = order.receiver.get();
        // The lending operations map taker and maker amount as makerAmount: inputAmount, takerAmount: outputAmount
        _composer(user, takingAmount, makingAmount, extension);
    }

    function preInteractionTargetAndData(
        bytes calldata data
    ) external pure returns (bytes memory) {
        return ExtensionLib.preInteractionTargetAndData(data);
    }

    function _composer(
        address callerAddress,
        uint256 takerAmount, // buy
        uint256 makerAmount, // sell
        bytes calldata lendingOps
    ) internal {
        uint256 length;
        uint256 maxIndex;
        uint256 currentOffset;
        bytes32 d;
        assembly {
            length := sub(lendingOps.length, 84)
            maxIndex := add(length, lendingOps.offset)
            currentOffset := add(84, lendingOps.offset)
            d := calldataload(add(84, lendingOps.offset))
        }
        console.logBytes32(d);

        console.log(address(this));
        console.log("lendingOps");
        console.logBytes(lendingOps);

        while (true) {
            uint256 operation;
            // fetch op metadata
            assembly {
                operation := shr(248, calldataload(currentOffset)) // last byte
                // we increment the current offset to skip the operation
                currentOffset := add(1, currentOffset)
            }
            console.log("operation", operation);
            if (operation == ComposerCommands.LENDING) {
                currentOffset = _lendingOperations(
                    callerAddress,
                    currentOffset,
                    takerAmount,
                    makerAmount
                );
            } else if (operation == ComposerCommands.TRANSFERS) {
                currentOffset = _transfers(
                    currentOffset,
                    callerAddress,
                    makerAmount
                );
            } else if (operation == ComposerCommands.PERMIT) {
                currentOffset = _permit(currentOffset, callerAddress);
            } else if (operation == ComposerCommands.FLASH_LOAN) {
                currentOffset = _universalFlashLoan(
                    currentOffset,
                    callerAddress,
                    makerAmount
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
        // approve self
        IERC20(order.takerAsset.get()).approve(_LIMIT_ORDER_PROTOCOL, type(uint).max);
        IERC20(order.makerAsset.get()).approve(_LIMIT_ORDER_PROTOCOL, type(uint).max);


        // extract extension
        (, bytes memory extension, ) = _parseArgs(takerTraits, args);
        if (extension.length < 65) {
            revert InvalidExtensionLength();
        }

        // last 65 bytes of the extension is the typedHash signature of the extension
        bytes memory extensionSignature = new bytes(65);
        assembly {
            // copy extension signature to bytes
            mcopy(
                add(extensionSignature, 0x20),
                sub(add(mload(extension), add(extension, 0x20)), 65),
                65
            )
            // shorten extension to data without signature
            mstore(extension, sub(mload(extension), 65))
        }

        bytes32 extensionHash = _hashTypedDataV4(keccak256(extension));
        // recover the signer of the extension
        address signer = _recoverSigner(extensionHash, extensionSignature);
        return
            IOrderMixin(_LIMIT_ORDER_PROTOCOL).fillContractOrderArgs(
                order,
                abi.encodePacked(signature, signer), // append the signer of the extension to the order signature
                amount,
                takerTraits,
                args
            );
    }

    function flashLoanFill(
        address asset,
        uint256 amount,
        bytes calldata params
    ) external {
        morphoFlashLoanSimple(asset, amount, params);
    }

    /// @dev Morpho Blue flash loan callback
    function onMorphoFlashLoan(uint256, bytes calldata data) external {
        require(
            msg.sender == 0x6c247b1F6182318877311737BaC0844bAa518F5e,
            "NOT MB"
        );
        // get order params
        (
            IOrderMixin.Order memory order,
            bytes memory signature,
            uint256 amount,
            TakerTraits takerTraits,
            bytes memory args
        ) = abi.decode(
                data,
                (IOrderMixin.Order, bytes, uint256, TakerTraits, bytes)
            );
        this.takeOrder(order, signature, amount, takerTraits, args);

        IERC20(order.takerAsset.get()).approve(msg.sender, type(uint256).max);
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
        public
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
