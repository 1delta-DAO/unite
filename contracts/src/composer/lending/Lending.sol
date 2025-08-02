// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {LenderOps, LenderIds} from "../lib/enums/DeltaEnums.sol";
import {AaveLending} from "./AaveLending.sol";
import {CompoundV2Lending} from "./CompoundV2Lending.sol";
import {CompoundV3Lending} from "./CompoundV3Lending.sol";
import {MorphoLending} from "./MorphoLending.sol";
import "../../Errors.sol";

abstract contract Lending is
    AaveLending,
    CompoundV2Lending,
    CompoundV3Lending,
    MorphoLending
{
    function _lendingOperations(
        address callerAddress,
        uint256 currentOffset,
        uint256 takerAmount, // buy
        uint256 makerAmount // sell
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
                return _depositToAaveV3(currentOffset, takerAmount, callerAddress);
            } else if (lender < LenderIds.UP_TO_AAVE_V2) {
                return _depositToAaveV2(currentOffset, takerAmount, callerAddress);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V3) {
                return _depositToCompoundV3(currentOffset, takerAmount);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V2) {
                return _depositToCompoundV2(currentOffset, takerAmount);
            } else {
                return
                    _encodeMorphoDepositCollateral(
                        currentOffset,
                        callerAddress,
                        takerAmount
                    );
            }
        }
        /**
         * Borrow
         */
        else if (lendingOperation == LenderOps.BORROW) {
            if (lender < LenderIds.UP_TO_AAVE_V2) {
                return
                    _borrowFromAave(currentOffset, callerAddress, makerAmount);
            } else if (lender < LenderIds.UP_TO_COMPOUND_V3) {
                return
                    _borrowFromCompoundV3(
                        currentOffset,
                        callerAddress,
                        makerAmount
                    );
            } else if (lender < LenderIds.UP_TO_COMPOUND_V2) {
                return
                    _borrowFromCompoundV2(
                        currentOffset,
                        callerAddress,
                        makerAmount
                    );
            } else {
                return
                    _morphoBorrow(currentOffset, callerAddress, makerAmount);
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
        } else {
            _invalidOperation();
        }
    }
}
