// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.30;

import {AssetTransfers} from "./AssetTransfers.sol";
import {TransferIds} from "../lib/enums/DeltaEnums.sol";
import "../../Errors.sol";

/**
 * @title Token transfer contract - should work across all EVMs - uses Uniswap style Permit2
 */
contract Transfers is AssetTransfers {
    function _transfers(
        uint256 currentOffset,
        address callerAddress,
        uint256 overrideAmount
    ) internal returns (uint256) {
        uint256 transferOperation;
        assembly {
            let firstSlice := calldataload(currentOffset)
            transferOperation := shr(248, firstSlice)
            currentOffset := add(currentOffset, 1)
        }
        if (transferOperation == TransferIds.TRANSFER_FROM) {
            return _transferFrom(currentOffset, callerAddress, overrideAmount);
        } else if (transferOperation == TransferIds.SWEEP) {
            return _sweep(currentOffset, overrideAmount);
        } else if (transferOperation == TransferIds.UNWRAP_WNATIVE) {
            return _unwrap(currentOffset, overrideAmount);
        } else if (transferOperation == TransferIds.PERMIT2_TRANSFER_FROM) {
            return
                _permit2TransferFrom(
                    currentOffset,
                    callerAddress,
                    overrideAmount
                );
        } else if (transferOperation == TransferIds.APPROVE) {
            return _approve(currentOffset);
        } else {
            _invalidOperation();
        }
    }
}
