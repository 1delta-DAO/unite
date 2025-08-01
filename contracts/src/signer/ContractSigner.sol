// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "../Errors.sol";

import {console} from "forge-std/console.sol";
abstract contract ContractSigner is IERC1271 {
    function isValidSignature(
        bytes32 orderHash,
        bytes calldata signature
    ) external pure returns (bytes4) {
        return _isValidSignature(orderHash, signature);
    }

    function _isValidSignature(
        bytes32 orderHash,
        bytes calldata signature
    ) internal pure returns (bytes4) {
        console.logBytes(signature);
        console.log("signature", signature.length);
        // 32 r, 32 s, 1 v, 20 signer,
        if (signature.length != 85) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;
        address signer;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := shr(248, calldataload(add(signature.offset, 0x40)))
            signer := shr(96, calldataload(add(signature.offset, 65)))
        }
        console.log("signer", signer);
        console.log("orderHash");
console.logBytes32(orderHash);
        address recoveredSigner = ECDSA.recover(orderHash, v, r, s);
        console.log("recoveredSigner", recoveredSigner);

        if (recoveredSigner == signer && recoveredSigner != address(0)) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }

    function _recoverSigner(
        bytes32 orderHash,
        bytes memory signature
    ) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            let offset := add(signature, 0x20)
            r := mload(offset)
            s := mload(add(offset, 0x20))
            v := shr(248, mload(add(offset, 0x40)))
        }

        return ECDSA.recover(orderHash, v, r, s);
    }
}
