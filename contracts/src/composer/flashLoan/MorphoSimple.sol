// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.30;

import {Masks} from "../lib/masks/Masks.sol";

/**
 * @title Morpho flash loans
 * @author 1delta Labs AG
 */
contract MorphoFlashLoanSimple is Masks {
        address private constant MORPHO_BLUE =
        0x6c247b1F6182318877311737BaC0844bAa518F5e;

    /*
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | asset                           |
     * | 20     | 20             | pool                            | <-- we allow ANY morpho style pool here
     * | 40     | 2              | paramsLength                    |
     * | 42     | paramsLength   | params                          |
     */
    function morphoFlashLoanSimple(
        address token,
        uint256 amount,
        bytes calldata params
    ) internal {
        assembly {
            // length of params
            let calldataLength := params.length
            // skip token, pool and params length
            let currentOffset := params.offset

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
            mstore(add(ptr, 100), calldataLength) // data length
            calldatacopy(add(ptr, 132), currentOffset, calldataLength) // calldata
            if iszero(
                call(
                    gas(),
                    MORPHO_BLUE,
                    0x0,
                    ptr,
                    add(calldataLength, 132),
                    0x0,
                    0x0 //
                )
            ) {
                returndatacopy(0, 0, returndatasize())
                revert(0x0, returndatasize())
            }
        }
    }
}
