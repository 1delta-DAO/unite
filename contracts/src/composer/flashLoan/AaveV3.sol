// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.30;

import {Masks} from "../lib/masks/Masks.sol";

/**
 * @title Aave V3 flash loan executor
 * @author 1delta Labs AG
 */
contract AaveV3FlashLoans is Masks {
    /*
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | asset                           |
     * | 20     | 20             | pool                            | <-- we allow ANY aave v2 style pool here
     * | 40     | 2              | paramsLength                    |
     * | 42     | paramsLength   | params                          |
     */
    function aaveV3FlashLoan(
        uint256 currentOffset,
        address callerAddress,
        uint256 amount
    ) internal returns (uint256) {
        assembly {
            // get token to loan
            let token := shr(96, calldataload(currentOffset))

            let slice := calldataload(add(currentOffset, 20))

            // target to call
            let pool := shr(96, slice)

            // length of params
            let calldataLength := and(UINT16_MASK, shr(80, slice))

            // skip token, pool and params length
            currentOffset := add(currentOffset, 42)

            let ptr := mload(0x40)
            // flashLoanSimple(...)
            mstore(
                ptr,
                0x42b0b77c00000000000000000000000000000000000000000000000000000000
            )
            mstore(add(ptr, 4), address()) // receiver is self
            mstore(add(ptr, 36), token) // asset
            mstore(add(ptr, 68), amount) // amount
            mstore(add(ptr, 100), 0xa0) // offset calldata
            mstore(add(ptr, 132), 0) // refCode
            mstore(add(ptr, 164), add(20, calldataLength)) // length calldata
            // caller at the beginning
            mstore(add(ptr, 196), shl(96, callerAddress))
            calldatacopy(add(ptr, 216), currentOffset, calldataLength) // calldata
            if iszero(
                call(
                    gas(),
                    pool,
                    0x0,
                    ptr,
                    add(calldataLength, 216), // = 7 * 32 + 4
                    0x0,
                    0x0 //
                )
            ) {
                returndatacopy(0, 0, returndatasize())
                revert(0x0, returndatasize())
            }

            // increment offset
            currentOffset := add(currentOffset, calldataLength)
        }
        return currentOffset;
    }
}
