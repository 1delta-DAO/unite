// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import "../Errors.sol";

abstract contract ContractSigner is IERC1271 {
    function isValidSignature(
        bytes32 orderHash,
        bytes calldata signature
    ) external pure returns (bytes4) {
        // 32 offset, 32 length, 32 r, 32 s, 1 v, 20 signer, padded to 32 bytes
        if (signature.length != 160) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;
        address signer;

        assembly {
            let offset := add(signature.offset, 0x40)
            r := calldataload(offset)
            s := calldataload(add(offset, 0x20))
            v := shr(248, calldataload(add(offset, 0x40)))
            signer := shr(96, calldataload(add(offset, 65)))
        }

        address recoveredSigner = ECDSA.recover(orderHash, v, r, s);

        if (recoveredSigner == signer && recoveredSigner != address(0)) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }
}
