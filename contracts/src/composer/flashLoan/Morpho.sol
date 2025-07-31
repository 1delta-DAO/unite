// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.30;

import {Masks} from "../lib/masks/Masks.sol";

/**
 * @title Morpho flash loans
 * @author 1delta Labs AG
 */
contract MorphoFlashLoans is Masks {
    /*
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | asset                           |
     * | 20     | 20             | pool                            | <-- we allow ANY morpho style pool here
     * | 40     | 2              | paramsLength                    |
     * | 42     | paramsLength   | params                          |
     */
    function morphoFlashLoan(
        uint256 currentOffset,
        address callerAddress,
        uint256 amount
    ) internal returns (uint256) {
        assembly {
            // get token to loan
            let token := shr(96, calldataload(currentOffset))
            // morpho-like pool as target
            let slice := calldataload(add(currentOffset, 20))
            let pool := shr(96, slice)
            // length of params
            let calldataLength := and(UINT16_MASK, shr(80, slice))
            // skip token, pool and params length
            currentOffset := add(currentOffset, 42)

            // morpho should be the primary choice
            let ptr := mload(0x40)

            /**
             * Prepare call
             */

            // flashLoan(...)
            mstore(
                ptr,
                0xe0232b4200000000000000000000000000000000000000000000000000000000
            )
            mstore(add(ptr, 4), token)
            mstore(add(ptr, 36), amount)
            mstore(add(ptr, 68), 0x60) // offset
            mstore(add(ptr, 100), add(20, calldataLength)) // data length
            mstore(add(ptr, 132), shl(96, callerAddress)) // caller
            calldatacopy(add(ptr, 152), currentOffset, calldataLength) // calldata
            if iszero(
                call(
                    gas(),
                    pool,
                    0x0,
                    ptr,
                    add(calldataLength, 152),
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
