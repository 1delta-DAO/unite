// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PermitConstants} from "./PermitConstants.sol";
import {ERC20Selectors} from "../selectors/ERC20Selectors.sol";

// solhint-disable max-line-length

/// @title PermitUtilsSlim
/// @notice A contract containing utilities for Permits
abstract contract PermitUtilsSlim is PermitConstants, ERC20Selectors {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SafePermitBadLength();
    error HasMsgValue();

    bytes4 internal constant HAS_MSG_VALUE = 0xf6a73902;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {}

    /**
     * @notice The function attempts to call the permit function on a given ERC20 token and executes a transfer afterwards
     * @dev The function is designed to support a variety of permit functions, namely: IERC20Permit, IDaiLikePermit, and IPermit2.
     * It accommodates both Compact and Full formats of these permit types.
     * Please note, it is expected that the `expiration` parameter for the compact Permit2 and the `deadline` parameter
     * for the compact Permit are to be incremented by one before invoking this function. This approach is motivated by
     * gas efficiency considerations; as the unlimited expiration period is likely to be the most common scenario, and
     * zeros are cheaper to pass in terms of gas cost. Thus, callers should increment the expiration or deadline by one
     * before invocation for optimized performance.
     * Note that the implementation does not perform dirty bits cleaning, so it is the responsibility of
     * the caller to make sure that the higher 96 bits of the `owner` and `spender` parameters are clean.
     * @param token The address of the ERC20 token on which to call the permit function.
     * @param amount Amount to pull from the caller - should be less than or equal the permit amount
     * @param permit The off-chain permit data, containing different fields depending on the type of permit function.
     */
    function _permitAndPull(
        address token,
        uint256 amount,
        bytes calldata permit
    ) internal {
        assembly ("memory-safe") {
            // solhint-disable-line no-inline-assembly
            // revert if native value provided
            if gt(callvalue(), 0) {
                mstore(0x0, HAS_MSG_VALUE)
                revert(0x0, 0x4)
            }

            let ptr := mload(0x40)
            // Switch case for different permit lengths, indicating different permit standards
            switch permit.length
            // Compact IERC20Permit
            case 100 {
                mstore(ptr, ERC20_PERMIT) // store selector
                mstore(add(ptr, 0x04), caller()) // store owner
                mstore(add(ptr, 0x24), address()) // store spender

                // Compact IERC20Permit.permit(uint256 value, uint32 deadline, uint256 r, uint256 vs)
                {
                    // stack too deep
                    let deadline := shr(
                        224,
                        calldataload(add(permit.offset, 0x20))
                    ) // loads permit.offset 0x20..0x23
                    let vs := calldataload(add(permit.offset, 0x44)) // loads permit.offset 0x44..0x63

                    calldatacopy(add(ptr, 0x44), permit.offset, 0x20) // store value     = copy permit.offset 0x00..0x19
                    mstore(add(ptr, 0x64), sub(deadline, 1)) // store deadline  = deadline - 1
                    mstore(add(ptr, 0x84), add(27, shr(255, vs))) // store v         = most significant bit of vs + 27 (27 or 28)
                    calldatacopy(add(ptr, 0xa4), add(permit.offset, 0x24), 0x20) // store r         = copy permit.offset 0x24..0x43
                    mstore(add(ptr, 0xc4), shr(1, shl(1, vs))) // store s         = vs without most significant bit
                }
                // IERC20Permit.permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
                let success := call(gas(), token, 0, ptr, 0xe4, 0, 0)
                if iszero(success) {
                    returndatacopy(0, 0x0, returndatasize())
                    revert(0, returndatasize())
                }
                ////////////////////////////////////////////////////
                // transferFrom on token
                ////////////////////////////////////////////////////
                // selector for transferFrom(address,address,uint256)
                mstore(ptr, ERC20_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller()) // store owner
                // spender still in place
                mstore(add(ptr, 0x44), amount) // store amount (we do not want to take the same as the permit one)

                success := call(gas(), token, 0x0, ptr, 0x64, ptr, 32)

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
                    returndatacopy(0, 0x0, rdsize)
                    revert(ptr, rdsize)
                }
            }
            // Compact IDaiLikePermit
            case 72 {
                mstore(ptr, DAI_PERMIT) // store selector
                mstore(add(ptr, 0x04), caller()) // store owner
                mstore(add(ptr, 0x24), address()) // store spender

                // Compact IDaiLikePermit.permit(uint32 nonce, uint32 expiry, uint256 r, uint256 vs)
                {
                    // stack too deep
                    let expiry := shr(
                        224,
                        calldataload(add(permit.offset, 0x04))
                    ) // loads permit.offset 0x04..0x07
                    let vs := calldataload(add(permit.offset, 0x28)) // loads permit.offset 0x28..0x47

                    mstore(
                        add(ptr, 0x44),
                        shr(224, calldataload(permit.offset))
                    ) // store nonce   = copy permit.offset 0x00..0x03
                    mstore(add(ptr, 0x64), sub(expiry, 1)) // store expiry  = expiry - 1
                    mstore(add(ptr, 0x84), true) // store allowed = true
                    mstore(add(ptr, 0xa4), add(27, shr(255, vs))) // store v       = most significant bit of vs + 27 (27 or 28)
                    calldatacopy(add(ptr, 0xc4), add(permit.offset, 0x08), 0x20) // store r       = copy permit.offset 0x08..0x27
                    mstore(add(ptr, 0xe4), shr(1, shl(1, vs))) // store s       = vs without most significant bit
                }
                // IDaiLikePermit.permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s)
                let success := call(gas(), token, 0, ptr, 0x104, 0, 0)
                if iszero(success) {
                    returndatacopy(0, 0x0, returndatasize())
                    revert(0, returndatasize())
                }
                ////////////////////////////////////////////////////
                // transferFrom on token
                ////////////////////////////////////////////////////
                // selector for transferFrom(address,address,uint256)
                mstore(ptr, ERC20_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller()) // store owner
                // spender still in place
                mstore(add(ptr, 0x44), amount) // store amount

                success := call(gas(), token, 0x0, ptr, 0x64, ptr, 32)

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
                    returndatacopy(0, 0x0, rdsize)
                    revert(ptr, rdsize)
                }
            }
            // IERC20Permit
            case 224 {
                mstore(ptr, ERC20_PERMIT)
                calldatacopy(add(ptr, 0x04), permit.offset, permit.length) // copy permit calldata
                // IERC20Permit.permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
                let success := call(gas(), token, 0, ptr, 0xe4, 0, 0)
                if iszero(success) {
                    returndatacopy(0, 0x0, returndatasize())
                    revert(0, returndatasize())
                }
                ////////////////////////////////////////////////////
                // transferFrom on token
                ////////////////////////////////////////////////////
                // selector for transferFrom(address,address,uint256)
                mstore(ptr, ERC20_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller()) // store owner
                // spender still in place
                mstore(add(ptr, 0x44), amount) // store amount (we do not want to take the same as the permit one)

                success := call(gas(), token, 0x0, ptr, 0x64, ptr, 32)

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
                    returndatacopy(0, 0x0, rdsize)
                    revert(ptr, rdsize)
                }
            }
            // IDaiLikePermit
            case 256 {
                mstore(ptr, DAI_PERMIT)
                calldatacopy(add(ptr, 0x04), permit.offset, permit.length) // copy permit calldata
                // IDaiLikePermit.permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s)
                let success := call(gas(), token, 0, ptr, 0x104, 0, 0)
                if iszero(success) {
                    returndatacopy(0, 0x0, returndatasize())
                    revert(0, returndatasize())
                }
                ////////////////////////////////////////////////////
                // transferFrom on token
                ////////////////////////////////////////////////////
                // selector for transferFrom(address,address,uint256)
                mstore(ptr, ERC20_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller()) // store owner
                // spender still in place
                mstore(add(ptr, 0x44), amount)

                success := call(gas(), token, 0x0, ptr, 0x64, ptr, 32)

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
                    returndatacopy(0, 0x0, rdsize)
                    revert(ptr, rdsize)
                }
            }
            // Compact IPermit2
            case 96 {
                // Compact IPermit2.permit(uint160 amount, uint32 expiration, uint32 nonce, uint32 sigDeadline, uint256 r, uint256 vs)
                mstore(ptr, PERMIT2_PERMIT) // store selector
                mstore(add(ptr, 0x04), caller()) // store owner
                mstore(add(ptr, 0x24), token) // store token

                calldatacopy(add(ptr, 0x50), permit.offset, 0x14) // store amount = copy permit.offset 0x00..0x13
                // and(0xffffffffffff, ...) - conversion to uint48
                mstore(
                    add(ptr, 0x64),
                    and(
                        0xffffffffffff,
                        sub(shr(224, calldataload(add(permit.offset, 0x14))), 1)
                    )
                ) // store expiration = ((permit.offset 0x14..0x17 - 1) & 0xffffffffffff)
                mstore(
                    add(ptr, 0x84),
                    shr(224, calldataload(add(permit.offset, 0x18)))
                ) // store nonce = copy permit.offset 0x18..0x1b
                mstore(add(ptr, 0xa4), address()) // store spender
                // and(0xffffffffffff, ...) - conversion to uint48
                mstore(
                    add(ptr, 0xc4),
                    and(
                        0xffffffffffff,
                        sub(shr(224, calldataload(add(permit.offset, 0x1c))), 1)
                    )
                ) // store sigDeadline = ((permit.offset 0x1c..0x1f - 1) & 0xffffffffffff)
                mstore(add(ptr, 0xe4), 0x100) // store offset = 256
                mstore(add(ptr, 0x104), 0x40) // store length = 64
                calldatacopy(add(ptr, 0x124), add(permit.offset, 0x20), 0x20) // store r      = copy permit.offset 0x20..0x3f
                calldatacopy(add(ptr, 0x144), add(permit.offset, 0x40), 0x20) // store vs     = copy permit.offset 0x40..0x5f
                // IPermit2.permit(address owner, PermitSingle calldata permitSingle, bytes calldata signature)
                if iszero(call(gas(), PERMIT2, 0, ptr, 0x164, 0, 0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                ////////////////////////////////////////////////////
                // transferFrom through permit2
                ////////////////////////////////////////////////////
                mstore(ptr, PERMIT2_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), address())
                mstore(add(ptr, 0x44), amount)
                mstore(add(ptr, 0x64), token)
                if iszero(call(gas(), PERMIT2, 0, ptr, 0x84, 0x0, 0x0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
            // IPermit2
            case 352 {
                mstore(ptr, PERMIT2_PERMIT)
                calldatacopy(add(ptr, 0x04), permit.offset, permit.length) // copy permit calldata
                // IPermit2.permit(address owner, PermitSingle calldata permitSingle, bytes calldata signature)
                if iszero(call(gas(), PERMIT2, 0, ptr, 0x164, 0, 0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                ////////////////////////////////////////////////////
                // transferFrom through permit2
                ////////////////////////////////////////////////////
                mstore(ptr, PERMIT2_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), address())
                mstore(add(ptr, 0x44), amount)
                mstore(add(ptr, 0x64), token)
                if iszero(call(gas(), PERMIT2, 0, ptr, 0x84, 0x0, 0x0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
            // Just transfer
            case 0 {
                // selector for transferFrom(address,address,uint256)
                mstore(ptr, ERC20_TRANSFER_FROM)
                mstore(add(ptr, 0x04), caller())
                mstore(add(ptr, 0x24), address())
                mstore(add(ptr, 0x44), amount)

                let success := call(gas(), token, 0x0, ptr, 0x64, ptr, 32)

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
                    returndatacopy(0, 0x0, rdsize)
                    revert(ptr, rdsize)
                }
            }
            // Unknown
            default {
                mstore(ptr, _PERMIT_LENGTH_ERROR)
                revert(ptr, 4)
            }
        }
    }
}
