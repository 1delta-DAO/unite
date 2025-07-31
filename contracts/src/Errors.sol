// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

error InvalidSignature();
error InvalidSignatureLength();
error InvalidOperation();
error OnlyLimitOrderProtocol();
error InvalidCalldata();

bytes4 constant INVALID_OPERATION = 0x398d4d32;

function _invalidOperation() pure {
    assembly {
        mstore(0, INVALID_OPERATION)
        revert(0, 0x4)
    }
}
