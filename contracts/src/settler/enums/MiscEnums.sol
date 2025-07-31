// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

enum SweepType {
    VALIDATE,
    AMOUNT
}

enum DexPayConfig {
    CALLER_PAYS,
    CONTRACT_PAYS,
    PRE_FUND,
    FLASH
}

enum DodoSelector {
    SELL_BASE,
    SELL_QUOTE
}

enum WrapOperation {
    NATIVE,
    ERC4626_DEPOSIT,
    ERC4626_REDEEM
}
