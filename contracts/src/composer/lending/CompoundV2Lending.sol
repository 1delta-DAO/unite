// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.30;

import {ERC20Selectors} from "../lib/selectors/ERC20Selectors.sol";
import {Masks} from "../lib/masks/Masks.sol";

// solhint-disable max-line-length

/**
 * @notice Lending base contract that wraps multiple Compound V2 lender types.
 * Most effective for Venus
 */
abstract contract CompoundV2Lending is ERC20Selectors, Masks {
    /*
     * Note this is for Venus Finance only as other Compound forks
     * do not have this feature.
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | underlying                      |
     * | 20     | 16             | amount                          |
     * | 36     | 20             | receiver                        |
     * | 76     | 20             | cToken                          |
     */
    function _borrowFromCompoundV2(
        uint256 currentOffset,
        address callerAddress,
        uint256 amount
    ) internal returns (uint256) {
        assembly {
            let ptr := mload(0x40)
            // Compound V3 types need to trasfer collateral tokens
            let underlying := shr(96, calldataload(currentOffset))
            // offset for amount at lower bytes
            let amountData := shr(128, calldataload(add(currentOffset, 20)))
            // receiver
            let receiver := shr(96, calldataload(add(currentOffset, 36)))

            let cToken := shr(96, calldataload(add(currentOffset, 56)))

            currentOffset := add(currentOffset, 76)

            let amount := and(UINT120_MASK, amountData)

            // selector for borrowBehlaf(address,uint256)
            mstore(
                ptr,
                0x856e5bb300000000000000000000000000000000000000000000000000000000
            )
            mstore(add(ptr, 0x4), callerAddress) // user
            mstore(add(ptr, 0x24), amount) // to this address
            if iszero(call(gas(), cToken, 0x0, ptr, 0x44, ptr, 0x0)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            if xor(address(), receiver) {
                switch underlying
                // native case
                case 0 {
                    if iszero(call(gas(), receiver, amount, 0, 0, 0, 0)) {
                        revert(0, 0)
                    }
                }
                // erc20 case
                default {
                    // 4) TRANSFER TO RECIPIENT
                    // selector for transfer(address,uint256)
                    mstore(ptr, ERC20_TRANSFER)
                    mstore(add(ptr, 0x04), receiver)
                    mstore(add(ptr, 0x24), amount)

                    let success := call(
                        gas(),
                        underlying,
                        0,
                        ptr,
                        0x44,
                        ptr,
                        32
                    )

                    let rdsize := returndatasize()

                    // Check for ERC20 success. ERC20 tokens should return a boolean,
                    // but some don't. We accept 0-length return data as success, or at
                    // least 32 bytes that starts with a 32-byte boolean true.
                    success := and(
                        success, // call itself succeeded
                        or(
                            iszero(rdsize), // no return data, or
                            and(
                                gt(rdsize, 31), // at least 32 bytes
                                eq(mload(ptr), 1) // starts with uint256(1)
                            )
                        )
                    )

                    if iszero(success) {
                        returndatacopy(0, 0, rdsize)
                        revert(0, rdsize)
                    }
                }
            }
        }
        return currentOffset;
    }

    /*
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | underlying                      |
     * | 20     | 16             | amount                          |
     * | 36     | 20             | receiver                        |
     * | 76     | 20             | cToken                          |
     */
    function _withdrawFromCompoundV2(
        uint256 currentOffset,
        address callerAddress
    ) internal returns (uint256) {
        assembly {
            let ptr := mload(0x40)
            // Compound V2 types need to trasfer collateral tokens
            let underlying := shr(96, calldataload(currentOffset))
            // offset for amount at lower bytes
            let amountData := shr(128, calldataload(add(currentOffset, 20)))
            // receiver
            let receiver := shr(96, calldataload(add(currentOffset, 36)))

            let cToken := shr(96, calldataload(add(currentOffset, 56)))

            currentOffset := add(currentOffset, 76)

            let amount := and(UINT120_MASK, amountData)
            if eq(amount, 0xffffffffffffffffffffffffffff) {
                // selector for balanceOfUnderlying(address)
                mstore(
                    0,
                    0x3af9e66900000000000000000000000000000000000000000000000000000000
                )
                // add caller address as parameter
                mstore(0x04, callerAddress)
                // call to token
                pop(
                    call(
                        gas(),
                        cToken, // collateral token
                        0x0,
                        0x0,
                        0x24,
                        0x0,
                        0x20
                    )
                )
                // load the retrieved balance
                amount := mload(0x0)
            }

            // 1) CALCULTAE TRANSFER AMOUNT
            // Store fnSig (=bytes4(abi.encodeWithSignature("exchangeRateCurrent()"))) at params
            // - here we store 32 bytes : 4 bytes of fnSig and 28 bytes of RIGHT padding
            mstore(
                0x0,
                0xbd6d894d00000000000000000000000000000000000000000000000000000000 // with padding
            )
            // call to collateralToken
            // accrues interest. No real risk of failure.
            pop(
                call(
                    gas(),
                    cToken,
                    0x0,
                    0x0,
                    0x24,
                    0x0, // store back to ptr
                    0x20
                )
            )

            // load the retrieved protocol share
            let refAmount := mload(0x0)

            // calculate collateral token amount, rounding up
            let cTokenTransferAmount := add(
                div(
                    mul(amount, 1000000000000000000), // multiply with 1e18
                    refAmount // divide by rate
                ),
                1
            )
            // FETCH BALANCE
            // selector for balanceOf(address)
            mstore(0x0, ERC20_BALANCE_OF)
            // add _from address as parameter
            mstore(0x4, callerAddress)

            // call to collateralToken
            pop(staticcall(gas(), cToken, 0x0, 0x24, 0x0, 0x20))

            // load the retrieved balance
            refAmount := mload(0x0)

            // floor to the balance
            if gt(cTokenTransferAmount, refAmount) {
                cTokenTransferAmount := refAmount
            }

            // 2) TRANSFER VTOKENS

            // selector for transferFrom(address,address,uint256)
            mstore(ptr, ERC20_TRANSFER_FROM)
            mstore(add(ptr, 0x04), callerAddress) // from user
            mstore(add(ptr, 0x24), address()) // to this address
            mstore(add(ptr, 0x44), cTokenTransferAmount)

            let success := call(gas(), cToken, 0, ptr, 0x64, ptr, 32)

            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            // 3) REDEEM
            // selector for redeem(uint256)
            mstore(
                0,
                0xdb006a7500000000000000000000000000000000000000000000000000000000
            )
            mstore(0x4, cTokenTransferAmount)

            if iszero(
                call(
                    gas(),
                    cToken,
                    0x0,
                    0x0, // input = selector
                    0x24, // input selector + uint256
                    0x0, // output
                    0x0 // output size = zero
                )
            ) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            // transfer tokens only if the receiver is not this address
            if xor(address(), receiver) {
                // 4) TRANSFER TO RECIPIENT
                // selector for transfer(address,uint256)
                mstore(ptr, ERC20_TRANSFER)
                mstore(add(ptr, 0x04), receiver)
                mstore(add(ptr, 0x24), amount)

                success := call(gas(), underlying, 0, ptr, 0x44, ptr, 32)

                let rdsize := returndatasize()

                // Check for ERC20 success. ERC20 tokens should return a boolean,
                // but some don't. We accept 0-length return data as success, or at
                // least 32 bytes that starts with a 32-byte boolean true.
                success := and(
                    success, // call itself succeeded
                    or(
                        iszero(rdsize), // no return data, or
                        and(
                            gt(rdsize, 31), // at least 32 bytes
                            eq(mload(ptr), 1) // starts with uint256(1)
                        )
                    )
                )

                if iszero(success) {
                    returndatacopy(0, 0, rdsize)
                    revert(0, rdsize)
                }
            }
        }
        return currentOffset;
    }

    /*
     * Note: Some Compound V2 forks might not have this feature and need a separate
     * function.
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | underlying                      |
     * | 20     | 20             | receiver                        |
     * | 40     | 20             | cToken                          |
     */
    /// @notice Withdraw from lender lastgiven user address and lender Id
    function _depositToCompoundV2(
        uint256 currentOffset,
        uint256 amount
    ) internal returns (uint256) {
        assembly {
            let underlying := shr(96, calldataload(currentOffset))
            // receiver
            let receiver := shr(96, calldataload(add(currentOffset, 20)))
            // get cToken
            let cToken := shr(96, calldataload(add(currentOffset, 40)))
            currentOffset := add(currentOffset, 60)

            switch underlying
            // case native
            case 0 {
                amount := and(UINT120_MASK, amount)
                // zero is this balance
                if iszero(amount) {
                    amount := selfbalance()
                }

                // selector for mint()
                mstore(
                    0,
                    0x1249c58b00000000000000000000000000000000000000000000000000000000
                )

                if iszero(call(gas(), cToken, amount, 0x0, 0x4, 0x0, 0x0)) {
                    returndatacopy(0x0, 0, returndatasize())
                    revert(0x0, returndatasize())
                }

                // need to transfer collateral to receiver
                if xor(receiver, address()) {
                    // selector for balanceOf(address)
                    mstore(0, ERC20_BALANCE_OF)
                    // add this address as parameter
                    mstore(0x04, address())
                    // call to token
                    pop(staticcall(gas(), cToken, 0x0, 0x24, 0x0, 0x20))
                    // load the retrieved balance
                    let cBalance := mload(0x0)

                    let ptr := mload(0x40)
                    // TRANSFER COLLATERAL
                    // selector for transfer(address,uint256)
                    mstore(ptr, ERC20_TRANSFER)
                    mstore(add(ptr, 0x04), receiver)
                    mstore(add(ptr, 0x24), cBalance)

                    let success := call(gas(), cToken, 0, ptr, 0x44, ptr, 32)

                    let rdsize := returndatasize()

                    if iszero(
                        and(
                            success, // call itself succeeded
                            or(
                                iszero(rdsize), // no return data, or
                                and(
                                    gt(rdsize, 31), // at least 32 bytes
                                    eq(mload(ptr), 1) // starts with uint256(1)
                                )
                            )
                        )
                    ) {
                        returndatacopy(0, 0, rdsize)
                        revert(0, rdsize)
                    }
                }
            }
            // erc20 case
            default {
                amount := and(UINT120_MASK, amount)
                // zero is this balance
                if iszero(amount) {
                    // selector for balanceOf(address)
                    mstore(0, ERC20_BALANCE_OF)
                    // add this address as parameter
                    mstore(0x04, address())
                    // call to token
                    pop(staticcall(gas(), underlying, 0x0, 0x24, 0x0, 0x20))
                    // load the retrieved balance
                    amount := mload(0x0)
                }

                let ptr := mload(0x40)

                // selector for mintBehalf(address,uint256)
                mstore(
                    ptr,
                    0x23323e0300000000000000000000000000000000000000000000000000000000
                )
                mstore(add(ptr, 0x04), receiver)
                mstore(add(ptr, 0x24), amount)

                if iszero(call(gas(), cToken, 0x0, ptr, 0x44, 0x0, 0x0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }
        return currentOffset;
    }

    /*
     * | Offset | Length (bytes) | Description                     |
     * |--------|----------------|---------------------------------|
     * | 0      | 20             | underlying                      |
     * | 20     | 16             | amount                          |
     * | 36     | 20             | receiver                        |
     * | 76     | 20             | cToken                          |
     */
    function _repayToCompoundV2(
        uint256 currentOffset
    ) internal returns (uint256) {
        assembly {
            let underlying := shr(96, calldataload(currentOffset))
            // offset for amount at lower bytes
            let amountData := shr(128, calldataload(add(currentOffset, 20)))
            // receiver
            let receiver := shr(96, calldataload(add(currentOffset, 36)))
            // get comet
            let cToken := shr(96, calldataload(add(currentOffset, 56)))
            currentOffset := add(currentOffset, 76)

            let ptr := mload(0x40)

            switch underlying
            // case native
            case 0 {
                let amount := and(UINT120_MASK, amountData)
                switch amount
                case 0 {
                    // load the retrieved balance
                    amount := selfbalance()
                }
                // safe repay the maximum
                case 0xffffffffffffffffffffffffffff {
                    // contract balance
                    amount := selfbalance()

                    // selector for borrowBalanceCurrent(address)
                    mstore(
                        0,
                        0x17bfdfbc00000000000000000000000000000000000000000000000000000000
                    )
                    // add this address as parameter
                    mstore(0x04, receiver)
                    // call to token
                    pop(call(gas(), cToken, 0x0, 0x0, 0x24, 0x0, 0x20))

                    // borrow balance smaller than amount available - use max
                    // otherwise, repay whatever is in the contract
                    if lt(mload(0x0), amount) {
                        amount := MAX_UINT256
                    }
                }

                // selector for repayBorrowBehalf(address)
                mstore(
                    0,
                    0xe597461900000000000000000000000000000000000000000000000000000000
                )
                mstore(4, receiver) // user

                if iszero(
                    call(
                        gas(),
                        cToken,
                        amount,
                        0, // input = empty for fallback
                        0x24, // input size = selector + address + uint256
                        0, // output
                        0x0 // output size = zero
                    )
                ) {
                    returndatacopy(0x0, 0, returndatasize())
                    revert(0x0, returndatasize())
                }
            }
            // case ERC20
            default {
                let amount := and(UINT120_MASK, amountData)
                switch amount
                case 0 {
                    // selector for balanceOf(address)
                    mstore(0, ERC20_BALANCE_OF)
                    // add this address as parameter
                    mstore(0x04, address())
                    // call to token
                    pop(staticcall(gas(), underlying, 0x0, 0x24, 0x0, 0x20))
                    // load the retrieved balance
                    amount := mload(0x0)
                }
                // safe repay the maximum
                case 0xffffffffffffffffffffffffffff {
                    // selector for balanceOf(address)
                    mstore(0, ERC20_BALANCE_OF)
                    // add this address as parameter
                    mstore(0x04, address())
                    // call to token
                    pop(staticcall(gas(), underlying, 0x0, 0x24, 0x0, 0x20))
                    // load the retrieved balance
                    amount := mload(0x0)

                    // selector for borrowBalanceCurrent(address)
                    mstore(
                        0,
                        0x17bfdfbc00000000000000000000000000000000000000000000000000000000
                    )
                    // add this address as parameter
                    mstore(0x04, receiver)
                    // call to collateral token
                    pop(call(gas(), cToken, 0x0, 0x0, 0x24, 0x0, 0x20))

                    // borrow balance smaller than amount available - use max
                    // otherwise, repay whatever is in the contract
                    if lt(mload(0x0), amount) {
                        amount := MAX_UINT256
                    }
                }

                // selector for repayBorrowBehalf(address,uint256)
                mstore(
                    ptr,
                    0x2608f81800000000000000000000000000000000000000000000000000000000
                )
                mstore(add(ptr, 0x4), receiver) // user
                mstore(add(ptr, 0x24), amount) // to this address

                if iszero(
                    call(
                        gas(),
                        cToken,
                        0x0,
                        ptr, // input = empty for fallback
                        0x44, // input size = selector + address + uint256
                        ptr, // output
                        0x0 // output size = zero
                    )
                ) {
                    returndatacopy(0x0, 0, returndatasize())
                    revert(0x0, returndatasize())
                }
            }
        }
        return currentOffset;
    }
}
