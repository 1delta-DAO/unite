// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.30;

import {MorphoFlashLoans} from "./Morpho.sol";
import {AaveV3FlashLoans} from "./AaveV3.sol";
import {AaveV2FlashLoans} from "./AaveV2.sol";
import {BalancerV2FlashLoans} from "./BalancerV2.sol";

import {FlashLoanCallbacks} from "./FlashLoanCallbacks.sol";
import {FlashLoanIds} from "../lib/enums/DeltaEnums.sol";
import "../../Errors.sol";

/**
 * @title Flash loan aggregator
 * @author 1delta Labs AG
 */
contract UniversalFlashLoan is
    MorphoFlashLoans,
    AaveV3FlashLoans,
    AaveV2FlashLoans,
    BalancerV2FlashLoans,
    FlashLoanCallbacks //
{
    /**
     * All flash ones in one function
     */
    function _universalFlashLoan(
        uint256 currentOffset,
        address callerAddress
    ) internal virtual returns (uint256) {
        uint256 flashLoanType; // architecture type
        assembly {
            flashLoanType := shr(248, calldataload(currentOffset)) // already masks uint8 as last byte
            currentOffset := add(currentOffset, 1)
        }

        if (flashLoanType == FlashLoanIds.MORPHO) {
            return morphoFlashLoan(currentOffset, callerAddress);
        } else if (flashLoanType == FlashLoanIds.AAVE_V3) {
            return aaveV3FlashLoan(currentOffset, callerAddress);
        } else if (flashLoanType == FlashLoanIds.AAVE_V2) {
            return aaveV2FlashLoan(currentOffset, callerAddress);
        } else if (flashLoanType == FlashLoanIds.BALANCER_V2) {
            return balancerV2FlashLoan(currentOffset, callerAddress);
        } else {
            _invalidOperation();
        }
    }
}
