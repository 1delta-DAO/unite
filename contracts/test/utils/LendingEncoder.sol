// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ComposerCommands, LenderIds, LenderOps} from "../../src/composer/lib/enums/DeltaEnums.sol";

library LendingEncoder {
    function encodeAaveBorrow(
        address asset,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.BORROW),
                uint16(LenderIds.UP_TO_AAVE_V3 - 1),
                asset,
                pool,
                uint8(2)
            );
    }

        function encodeTransferIn(
        address asset,
        uint256 amount,
        address receiver
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                asset,
                receiver,
                uint128(amount)
            );
    }


    function encodeAaveDeposit(
        address asset,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.DEPOSIT),
                uint16(LenderIds.UP_TO_AAVE_V3 - 1),
                asset,
                pool
            );
    }
}
