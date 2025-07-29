// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ContractSigner} from "../src/ContractSigner.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract TestSigner is ContractSigner {}

contract ContractSignerTest is Test {
    TestSigner public contractSigner;
    uint256 public signerPrivateKey;
    address public signerAddress;

    bytes32 public testHash;

    event Log(string message, bytes data);
    event LogAddress(string message, address addr);
    event LogBytes32(string message, bytes32 data);

    function setUp() public {
        VmSafe.Wallet memory wallet = vm.createWallet("signer");
        signerPrivateKey = wallet.privateKey;
        signerAddress = wallet.addr;

        contractSigner = new TestSigner();

        // Create a test hash to sign
        testHash = keccak256("HashMe!");

        console.log("Signer address:", signerAddress);
        console.log("Test hash:", vm.toString(testHash));

        vm.label(signerAddress, "signer");
    }

    function testValidSignature() public view {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, testHash);

        bytes memory signature = abi.encodePacked(r, s, v, signerAddress);

        console.log("Signature length:", signature.length);

        bytes4 result = contractSigner.isValidSignature(testHash, signature);

        assertEq(
            result,
            IERC1271.isValidSignature.selector,
            "Signature should be valid"
        );
    }
}
