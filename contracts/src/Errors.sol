// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

error InvalidSignature();
error InvalidSignatureLength();
error InvalidOperation();
error OnlyLimitOrderProtocol();
error InvalidCalldata();
error InvalidCaller();
error InvalidInitiator();
error InvalidFlashLoan();
error InvalidExtensionLength();
error Slippage();
error NativeTransferFailed();

// InvalidOperation()
bytes4 constant INVALID_OPERATION = 0x398d4d32;

// InvalidCaller()
bytes4 constant INVALID_CALLER = 0x48f5c3ed;

// InvalidInitiator()
bytes4 constant INVALID_INITIATOR = 0xbfda1f28;

// InvalidFlashLoan()
bytes4 constant INVALID_FLASH_LOAN = 0xbafe1c53;

// Slippage()
bytes4 constant SLIPPAGE = 0x7dd37f70;
// NativeTransferFailed()
bytes4 constant NATIVE_TRANSFER = 0xf4b3b1bc;

function _invalidOperation() pure {
    assembly {
        mstore(0, INVALID_OPERATION)
        revert(0, 0x4)
    }
}
