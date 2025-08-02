// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {MarginSettler} from "../src/settler/MarginSettler.sol";
import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {ExtensionLib} from "@1inch/lo/libraries/ExtensionLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {CalldataLib} from "../src/composer/utils/CalldataLib.sol";
import {SweepType} from "../src/composer/lib/enums/MiscEnums.sol";
import {MarginSettlerTest} from "./MarginSettler.t.sol";

contract SigConstructionTest is MarginSettlerTest {
    uint256 internal constant zero = 0;
    function test_sig_construct() external {
        VmSafe.Wallet memory wallet = vm.createWallet("signer");
        uint256 signerPrivateKey = wallet.privateKey;
        address signerAddress = wallet.addr;

        IOrderMixin.Order memory order = _createOrder();

        // the calldata follows this pattern
        // enum DynamicField {
        //     MakerAssetSuffix,
        //     TakerAssetSuffix,
        //     MakingAmountData,
        //     TakingAmountData,
        //     Predicate,
        //     MakerPermit,
        //     PreInteractionData,
        //     PostInteractionData,
        //     CustomData
        // }

        bytes memory extensionCalldata = abi.encodePacked(
            zero, // MakerAssetSuffix
            zero, // TakerAssetSuffix
            zero, // MakingAmountData
            zero, // TakingAmountData
            zero, // Predicate (makerPermit is 0x)
            address(marginSettler), // PreInteractionData
            keccak256("000"),
            keccak256("1")
        );
        console.logBytes(extensionCalldata);
        // errors
        // console.logBytes4(bytes4(keccak256("InvalidExtensionHash()")));
        // console.logBytes4(bytes4(keccak256("UnexpectedOrderExtension()")));
        // console.logBytes4(bytes4(keccak256("MissingOrderExtension()")));

        // console.logBytes4(bytes4(keccak256("PrivateOrder()")));
        // console.logBytes4(bytes4(keccak256("OrderExpired()")));
        // console.logBytes4(
        //     bytes4(keccak256("EpochManagerAndBitInvalidatorsAreIncompatible()"))
        // );
        // console.logBytes4(bytes4(keccak256("WrongSeriesNonce()")));
        // console.logBytes4(bytes4(keccak256("PredicateIsNotTrue()")));
        // console.logBytes4(bytes4(keccak256("TakingAmountTooHigh()")));
        // console.logBytes4(bytes4(keccak256("MakingAmountTooLow()")));
        // console.logBytes4(bytes4(keccak256("TakingAmountExceeded()")));
        // console.logBytes4(bytes4(keccak256("PartialFillNotAllowed()")));
        // console.logBytes4(bytes4(keccak256("SwapWithZeroAmount()")));
        // console.logBytes4(bytes4(keccak256("InvalidPermit2Transfer()")));
        // console.logBytes4(
        //     bytes4(keccak256("TransferFromTakerToMakerFailed()"))
        // );
        // console.logBytes4(bytes4(keccak256("IncorrectCalldataParams()")));
        // console.logBytes4(bytes4(keccak256("OffsetOutOfBounds()")));

        bytes32 extensionHash = marginSettler.hashExtension(extensionCalldata);
        console.logBytes32(extensionHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPrivateKey,
            extensionHash
        );
        bytes memory extensionSignature = abi.encodePacked(r, s, v);

        bytes memory extensionArgs = abi.encodePacked(
            // address(marginSettler),
            extensionCalldata,
            extensionSignature
        );

        // lower 160 bits are the ext hash
        order.salt =
            (~type(uint160).max & order.salt) |
            (type(uint160).max & uint256(keccak256(extensionArgs)));
        bytes32 orderHash = marginSettler.hashOrder(order);

        (v, r, s) = vm.sign(signerPrivateKey, orderHash);
        bytes memory orderSignature = abi.encodePacked(r, s, v);

        console.log("extensionSignature", extensionSignature.length);
        console.log("signerAddress", signerAddress);
        console.log("orderHash");
        console.logBytes32(orderHash);
        console.logBytes(extensionSignature);

        console.log("-------");
        console.logBytes32(bytes32(type(uint160).max & uint256(extensionHash)));
        console.logBytes32(bytes32(order.salt));
        console.logBytes32(keccak256(extensionArgs));
        console.log(
            "uint256(keccak256(extension)) & type(uint160).max != order.salt & type(uint160).max",
            uint256(keccak256(extensionArgs)) & type(uint160).max !=
                order.salt & type(uint160).max
        );
        console.log("-------");

        TakerTraits takerTraits = _createTakerTraits(extensionArgs.length, 0);

        // test calls
        // (, bytes memory a, ) = marginSettler._parseArgs(
        //     takerTraits,
        //     extensionArgs
        // );
        // marginSettler.preInteractionTargetAndData(a);
        // console.logBytes(extensionArgs);
        marginSettler.takeOrder(
            order,
            orderSignature,
            order.takingAmount,
            takerTraits,
            extensionArgs
        );
    }
}
