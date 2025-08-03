// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

/**
 * Permit classifier enums
 */
library TransferIds {
    uint256 internal constant TRANSFER_FROM = 0;
    uint256 internal constant SWEEP = 1;
    uint256 internal constant WRAP_NATIVE = 2;
    uint256 internal constant UNWRAP_WNATIVE = 3;
    uint256 internal constant PERMIT2_TRANSFER_FROM = 4;
    uint256 internal constant APPROVE = 5;
}

/**
 * Permit classifier enums
 */
library PermitIds {
    uint256 internal constant TOKEN_PERMIT = 0;
    uint256 internal constant AAVE_V3_CREDIT_PERMIT = 1;
    uint256 internal constant ALLOW_CREDIT_PERMIT = 2;
}

/**
 * Lender classifier enums, expected to be encoded as uint16
 */
library LenderIds {
    uint256 internal constant UP_TO_AAVE_V3 = 1000;
    uint256 internal constant UP_TO_AAVE_V2 = 2000;
    uint256 internal constant UP_TO_COMPOUND_V3 = 3000;
    uint256 internal constant UP_TO_COMPOUND_V2 = 4000;
    uint256 internal constant UP_TO_MORPHO = 5000;
}

/**
 * Operations enums, encoded as uint8
 */
library LenderOps {
    uint256 internal constant DEPOSIT = 0;
    uint256 internal constant BORROW = 1;
    uint256 internal constant REPAY = 2;
    uint256 internal constant WITHDRAW = 3;
    uint256 internal constant DEPOSIT_LENDING_TOKEN = 4;
    uint256 internal constant WITHDRAW_LENDING_TOKEN = 5;
}

/**
 * Lender classifier enums, expected to be encoded as uint16
 */
library FlashLoanIds {
    uint256 internal constant MORPHO = 0;
    uint256 internal constant BALANCER_V2 = 1;
    uint256 internal constant AAVE_V3 = 2;
    uint256 internal constant AAVE_V2 = 3;
}

/**
 * ERC4626 classifier enums
 */
library ERC4626Ids {
    uint256 internal constant DEPOSIT = 0;
    uint256 internal constant WITHDRAW = 1;
}

/// @title Commands for OneDeltaComposer
library ComposerCommands {
    uint256 internal constant LENDING = 0x30;
    uint256 internal constant TRANSFERS = 0x40;
    uint256 internal constant PERMIT = 0x50;
}
