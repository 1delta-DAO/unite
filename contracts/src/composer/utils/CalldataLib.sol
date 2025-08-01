// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../lib/enums/DeltaEnums.sol";
import {DexPayConfig, SweepType, DodoSelector, WrapOperation} from "../lib/enums/MiscEnums.sol";

library CalldataLib {
    function encodeExternalCall(
        address target,
        uint256 value,
        bool useSelfBalance,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.EXT_CALL),
                target,
                generateAmountBitmap(uint128(value), false, useSelfBalance),
                uint16(data.length),
                data
            );
    }

    function encodePermit(
        uint256 permitId,
        address target,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.PERMIT),
                uint8(permitId),
                target,
                uint16(data.length),
                data
            );
    }

    function encodePermit2TransferFrom(
        address token,
        address receiver
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                uint8(TransferIds.PERMIT2_TRANSFER_FROM),
                token,
                receiver
            );
    }

    function encodeTransferIn(
        address asset,
        address receiver
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                uint8(TransferIds.TRANSFER_FROM),
                asset,
                receiver
            );
    }

    function encodeSweep(
        address asset,
        address receiver,
        SweepType sweepType
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                uint8(TransferIds.SWEEP),
                asset,
                receiver,
                sweepType
            );
    }

    // this just uses sweep with config "AMOUNT" so that it mimics the prior behavior
    function encodeWrap(
        address wrapTarget
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                uint8(TransferIds.SWEEP),
                address(0), // signals native asset
                wrapTarget,
                uint8(SweepType.AMOUNT) // sweep type = AMOUNT
            );
    }

    function encodeApprove(
        address asset,
        address target
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                uint8(TransferIds.APPROVE),
                asset,
                target
            );
    }

    function encodeUnwrap(
        address target,
        address receiver,
        SweepType sweepType
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.TRANSFERS),
                uint8(TransferIds.UNWRAP_WNATIVE),
                target,
                receiver,
                sweepType
            );
    }

    function encodeBalancerV2FlashLoan(
        address asset,
        uint8 poolId,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.FLASH_LOAN),
                uint8(FlashLoanIds.BALANCER_V2),
                asset,
                uint16(data.length + 1),
                encodeUint8AndBytes(poolId, data)
            );
    }

    function encodeFlashLoan(
        address asset,
        address pool,
        uint8 poolType,
        uint8 poolId,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(asset, pool), // always approve
                uint8(ComposerCommands.FLASH_LOAN),
                poolType,
                asset,
                pool,
                uint16(data.length + 1),
                encodeUint8AndBytes(poolId, data)
            );
    }

    function encodeUint8AndBytes(
        uint8 poolId,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(poolId), data);
    }

    function encodeMorphoMarket(
        address loanToken,
        address collateralToken,
        address oracle,
        address irm,
        uint256 lltv
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                loanToken,
                collateralToken,
                oracle,
                irm,
                uint128(lltv)
            );
    }

    function encodeMorphoDepositCollateral(
        bytes memory market,
        address receiver,
        bytes memory data,
        address morphoB,
        uint256 pId
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(getMorphoCollateral(market), morphoB), // always approve
                uint8(ComposerCommands.LENDING), // 1
                uint8(LenderOps.DEPOSIT), // 1
                uint16(LenderIds.UP_TO_MORPHO), // 2
                market, // 4 * 20 + 16
                receiver,
                morphoB,
                uint16(data.length > 0 ? data.length + 1 : 0), // 2 @ 1 + 4*20
                data.length == 0
                    ? new bytes(0)
                    : encodeUint8AndBytes(uint8(pId), data)
            );
    }

    function encodeMorphoDeposit(
        bytes memory market,
        bool isShares, //
        address receiver,
        bytes memory data,
        address morphoB,
        uint256 pId
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(getMorphoLoanAsset(market), morphoB), // always approve
                uint8(ComposerCommands.LENDING), // 1
                uint8(LenderOps.DEPOSIT_LENDING_TOKEN), // 1
                uint16(LenderIds.UP_TO_MORPHO), // 2
                market, // 4 * 20 + 16
                receiver,
                morphoB,
                uint16(data.length > 0 ? data.length + 1 : 0), // 2 @ 1 + 4*20
                data.length == 0
                    ? new bytes(0)
                    : encodeUint8AndBytes(uint8(pId), data)
            );
    }

    function encodeErc4646Deposit(
        address asset,
        address vault,
        bool isShares, //
        uint256 assets,
        address receiver
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(asset, vault), // always approve
                uint8(ComposerCommands.ERC4626), // 1
                uint8(0), // 1
                asset, // 20
                vault, // 20
                generateAmountBitmap(uint128(assets), isShares, false),
                receiver // 20
            );
    }

    function encodeErc4646Withdraw(
        address vault,
        bool isShares, //
        uint256 assets,
        address receiver
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.ERC4626), // 1
                uint8(1), // 1
                vault, // 20
                generateAmountBitmap(uint128(assets), isShares, false),
                receiver // 20
            );
    }

    function encodeMorphoWithdraw(
        bytes memory market,
        bool isShares, //
        uint256 assets,
        address receiver,
        address morphoB
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING), // 1
                uint8(LenderOps.WITHDRAW_LENDING_TOKEN), // 1
                uint16(LenderIds.UP_TO_MORPHO), // 2
                market, // 4 * 20 + 16
                generateAmountBitmap(uint128(assets), isShares, false),
                receiver, // 20
                morphoB
            );
    }

    function encodeMorphoWithdrawCollateral(
        bytes memory market, //
        uint256 assets,
        address receiver,
        address morphoB
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING), // 1
                uint8(LenderOps.WITHDRAW), // 1
                uint16(LenderIds.UP_TO_MORPHO), // 2
                market, // 4 * 20 + 16
                uint128(assets), // 16
                receiver, // 20
                morphoB
            );
    }

    function encodeMorphoBorrow(
        bytes memory market,
        bool isShares, //
        address receiver,
        address morphoB
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING), // 1
                uint8(LenderOps.BORROW), // 1
                uint16(LenderIds.UP_TO_MORPHO), // 2
                market, // 4 * 20 + 16
                receiver,
                morphoB
            );
    }

    function encodeMorphoRepay(
        bytes memory market,
        bool isShares, //
        uint256 assets,
        address receiver,
        bytes memory data,
        address morphoB,
        uint256 pId
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(getMorphoLoanAsset(market), morphoB), // always approve
                uint8(ComposerCommands.LENDING), // 1
                uint8(LenderOps.REPAY), // 1
                uint16(LenderIds.UP_TO_MORPHO), // 2
                market, // 4 * 20 + 16
                generateAmountBitmap(uint128(assets), isShares, false),
                receiver,
                morphoB,
                uint16(data.length > 0 ? data.length + 1 : 0), // 2 @ 1 + 4*20
                data.length == 0
                    ? new bytes(0)
                    : encodeUint8AndBytes(uint8(pId), data)
            );
    }

    function encodeAaveDeposit(
        address token,
        address receiver,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(token, pool),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.DEPOSIT),
                uint16(LenderIds.UP_TO_AAVE_V3 - 1),
                token,
                receiver,
                pool //
            );
    }

    function encodeAaveBorrow(
        address token,
        address receiver,
        uint256 mode,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.BORROW),
                uint16(LenderIds.UP_TO_AAVE_V3 - 1),
                token,
                receiver,
                uint8(mode),
                pool //
            );
    }

    function encodeAaveRepay(
        address token,
        uint256 amount,
        address receiver,
        uint256 mode,
        address dToken,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(token, pool),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.REPAY),
                uint16(LenderIds.UP_TO_AAVE_V3 - 1),
                token,
                uint128(amount),
                receiver,
                uint8(mode),
                dToken,
                pool //
            );
    }

    function encodeAaveWithdraw(
        address token,
        uint256 amount,
        address receiver,
        address aToken,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.WITHDRAW),
                uint16(LenderIds.UP_TO_AAVE_V3 - 1),
                token,
                uint128(amount),
                receiver,
                aToken,
                pool //
            );
    }

    function encodeAaveV2Deposit(
        address token,
        address receiver,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(token, pool),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.DEPOSIT),
                uint16(LenderIds.UP_TO_AAVE_V2 - 1),
                token,
                receiver,
                pool //
            );
    }

    function encodeAaveV2Borrow(
        address token,
        address receiver,
        uint256 mode,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.BORROW),
                uint16(LenderIds.UP_TO_AAVE_V2 - 1),
                token,
                receiver,
                uint8(mode),
                pool //
            );
    }

    function encodeAaveV2Repay(
        address token,
        uint256 amount,
        address receiver,
        uint256 mode,
        address dToken,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(token, pool),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.REPAY),
                uint16(LenderIds.UP_TO_AAVE_V2 - 1),
                token,
                uint128(amount),
                receiver,
                uint8(mode),
                dToken,
                pool //
            );
    }

    function encodeAaveV2Withdraw(
        address token,
        uint256 amount,
        address receiver,
        address aToken,
        address pool
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.WITHDRAW),
                uint16(LenderIds.UP_TO_AAVE_V2 - 1),
                token,
                uint128(amount),
                receiver,
                aToken,
                pool //
            );
    }

    function encodeCompoundV3Deposit(
        address token,
        address receiver,
        address comet
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(token, comet),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.DEPOSIT),
                uint16(LenderIds.UP_TO_COMPOUND_V3 - 1),
                token,
                receiver,
                comet //
            );
    }

    function encodeCompoundV3Borrow(
        address token,
        address receiver,
        address comet
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.BORROW),
                uint16(LenderIds.UP_TO_COMPOUND_V3 - 1),
                token,
                receiver,
                comet //
            );
    }

    function encodeCompoundV3Repay(
        address token,
        uint256 amount,
        address receiver,
        address comet
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                encodeApprove(token, comet),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.REPAY),
                uint16(LenderIds.UP_TO_COMPOUND_V3 - 1),
                token,
                uint128(amount),
                receiver,
                comet //
            );
    }

    function encodeCompoundV3Withdraw(
        address token,
        uint256 amount,
        address receiver,
        address comet,
        bool isBase
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.WITHDRAW),
                uint16(LenderIds.UP_TO_COMPOUND_V3 - 1),
                token,
                uint128(amount),
                receiver,
                isBase ? uint8(1) : uint8(0),
                comet //
            );
    }

    function encodeCompoundV2Deposit(
        address token,
        address receiver,
        address cToken
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                // no approves for native
                token == address(0)
                    ? new bytes(0)
                    : encodeApprove(token, cToken),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.DEPOSIT),
                uint16(LenderIds.UP_TO_COMPOUND_V2 - 1),
                token,
                receiver,
                cToken //
            );
    }

    function encodeCompoundV2Borrow(
        address token,
        address receiver,
        address cToken
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.BORROW),
                uint16(LenderIds.UP_TO_COMPOUND_V2 - 1),
                token,
                receiver,
                cToken //
            );
    }

    function encodeCompoundV2Repay(
        address token,
        uint256 amount,
        address receiver,
        address cToken
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                // no approves for native
                token == address(0)
                    ? new bytes(0)
                    : encodeApprove(token, cToken),
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.REPAY),
                uint16(LenderIds.UP_TO_COMPOUND_V2 - 1),
                token,
                uint128(amount),
                receiver,
                cToken //
            );
    }

    function encodeCompoundV2Withdraw(
        address token,
        uint256 amount,
        address receiver,
        address cToken
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint8(ComposerCommands.LENDING),
                uint8(LenderOps.WITHDRAW),
                uint16(LenderIds.UP_TO_COMPOUND_V2 - 1),
                token,
                uint128(amount),
                receiver,
                cToken //
            );
    }

    /**
     * get the collateral asset from a packed Morpho market
     */
    function getMorphoCollateral(
        bytes memory market
    ) private pure returns (address collat) {
        assembly {
            collat := shr(96, mload(add(market, 52)))
        }
    }

    /**
     * get the loab asset from a packed Morpho market
     */
    function getMorphoLoanAsset(
        bytes memory market
    ) private pure returns (address collat) {
        assembly {
            collat := shr(96, mload(add(market, 32)))
        }
    }

    /// @dev Mask for using the injected amount
    uint256 private constant NATIVE_FLAG = 1 << 127;
    /// @dev Mask for shares
    uint256 private constant USE_SHARES_FLAG = 1 << 126;

    function generateAmountBitmap(
        uint128 amount,
        bool useShares,
        bool native
    ) internal pure returns (uint128 am) {
        am = amount;
        if (native) am = uint128((am & ~NATIVE_FLAG) | NATIVE_FLAG); // sets the first bit to 1
        if (useShares) am = uint128((am & ~USE_SHARES_FLAG) | USE_SHARES_FLAG); // sets the second bit to 1
        return am;
    }
}
