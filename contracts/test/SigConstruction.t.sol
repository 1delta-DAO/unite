// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {MarginSettler} from "../src/settler/MarginSettler.sol";
import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {CalldataLib} from "../src/composer/utils/CalldataLib.sol";
import {SweepType} from "../src/composer/lib/enums/MiscEnums.sol";
import {MarginSettlerTest} from "./MarginSettler.t.sol";

contract SigConstructionTest is MarginSettlerTest {
    function test_sig_construct() external {
        VmSafe.Wallet memory wallet = vm.createWallet("signer");
        uint256 signerPrivateKey = wallet.privateKey;
        address signerAddress = wallet.addr;

        IOrderMixin.Order memory order = _createOrder();

        bytes32 orderHash = keccak256(abi.encode(order));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, orderHash);

        bytes memory orderSignature = abi.encodePacked(r, s, v);

        bytes memory extensionCalldata = abi.encodePacked(
            orderHash,
            orderHash,
            orderHash
        );

        bytes32 extensionHash =marginSettler.hashExtension(extensionCalldata);
console.logBytes32(extensionHash);
        (v, r, s) = vm.sign(signerPrivateKey, extensionHash);

        bytes memory extensionSignature = abi.encodePacked(r, s, v);
        console.log("extensionSignature", extensionSignature.length);
        console.log("signerAddress", signerAddress);
        console.log("orderHash");
        console.logBytes32(orderHash);
        console.logBytes(extensionSignature);
        bytes memory extensionArgs = abi.encodePacked(
            extensionCalldata,
            extensionSignature
        );
        TakerTraits takerTraits = _createTakerTraits(extensionArgs.length, 0);
        console.logBytes(extensionArgs);
        marginSettler.takeOrder(
            order,
            orderSignature,
            0,
            takerTraits,
            extensionArgs
        );
    }
}
