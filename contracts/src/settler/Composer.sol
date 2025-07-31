// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

abstract contract Composer {
    function _lendingOperations(
        address user,
        uint256 currentOffset,
        uint256 amount
    ) internal returns (uint256) {
        uint256 lendingOperation;
        uint256 lender;
        assembly {
            let slice := calldataload(currentOffset)
            lendingOperation := shr(248, slice)
            lender := and(UINT16_MASK, shr(232, slice))
            currentOffset := add(currentOffset, 3)
        }
        /**
         * Deposit collateral
         */
        if (lendingOperation == LenderOps.DEPOSIT) {
            if (lender < LenderIds.UP_TO_AAVE_V3) {
                return _depositToAaveV3(currentOffset);
            } else if (lender < LenderIds.UP_TO_AAVE_V2) {
                return _depositToAaveV2(currentOffset);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V3) {
                return _depositToCompoundV3(currentOffset);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V2) {
                return _depositToCompoundV2(currentOffset);
            } else {
                return
                    _encodeMorphoDepositCollateral(
                        currentOffset,
                        callerAddress
                    );
            }
        }
        /**
         * Borrow
         */
        else if (lendingOperation == LenderOps.BORROW) {
            if (lender < LenderIds.UP_TO_AAVE_V2) {
                return _borrowFromAave(currentOffset, callerAddress);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V3) {
                return _borrowFromCompoundV3(currentOffset, callerAddress);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V2) {
                return _borrowFromCompoundV2(currentOffset, callerAddress);
            } else {
                return _morphoBorrow(currentOffset, callerAddress);
            }
        }
        /**
         * Repay
         */
        else if (lendingOperation == LenderOps.REPAY) {
            if (lender < LenderIds.UP_TO_AAVE_V2) {
                return _repayToAave(currentOffset, callerAddress);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V3) {
                return _repayToCompoundV3(currentOffset);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V2) {
                return _repayToCompoundV2(currentOffset);
            } else {
                return _morphoRepay(currentOffset, callerAddress);
            }
        }
        /**
         * Withdraw collateral
         */
        else if (lendingOperation == LenderOps.WITHDRAW) {
            if (lender < LenderIds.UP_TO_AAVE_V2) {
                return _withdrawFromAave(currentOffset, callerAddress);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V3) {
                return _withdrawFromCompoundV3(currentOffset, callerAddress);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V2) {
                return _withdrawFromCompoundV2(currentOffset, callerAddress);
            } else {
                return
                    _encodeMorphoWithdrawCollateral(
                        currentOffset,
                        callerAddress
                    );
            }
        }
        /**
         * deposit lendingToken
         */
        else if (lendingOperation == LenderOps.DEPOSIT_LENDING_TOKEN) {
            return _encodeMorphoDeposit(currentOffset, callerAddress);
        }
        /**
         * withdraw lendingToken
         */
        else if (lendingOperation == LenderOps.WITHDRAW_LENDING_TOKEN) {
            return _encodeMorphoWithdraw(currentOffset, callerAddress);
        } else {
            _invalidOperation();
        }
    }

    function _transfers(
        uint256 currentOffset,
        address callerAddress,
        uint256 amount
    ) internal returns (uint256) {}

    function _permit(
        uint256 currentOffset,
        address callerAddress,
        uint256 amount
    ) internal returns (uint256) {}
}
