// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {MarginSettler} from "../src/settler/MarginSettler.sol";
import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {ExtensionLib} from "@1inch/lo/libraries/ExtensionLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {SweepType} from "../src/composer/lib/enums/MiscEnums.sol";
import {MarginSettlerTest} from "./MarginSettler.t.sol";
import {LendingEncoder} from "./utils/LendingEncoder.sol";

/** ABI for aave delegation and supply to the pool */
interface IDelegation {
    function approveDelegation(address, uint) external;

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
}

contract FlashFillTest is MarginSettlerTest {
    // create the calldata for opening a position on Aave
    function _createOpen(
        address tokenIn,
        address tokenOut,
        address pool
    ) internal pure returns (bytes memory d) {
        d = abi.encodePacked(
            LendingEncoder.encodeAaveDeposit(tokenOut, pool),
            LendingEncoder.encodeAaveBorrow(tokenIn, pool)
        );

        return d;
    }
    /**
     * Test steps
     * 0) setup, create contracts and filler, signer (the user) address
     * 1) create order object (this is to sell (borrow) 360 USDC for (deposit]) 0.1 WETH on Aave V3 Arbitrum)
     * 2) create extension calldata (create operations that have all addreses needed)
     * 3) sign extension hash for validation
     * 4) attach extension hash to order.salt (as required by 1inch) and sing the order.
     * 5) create base setup for execution
     *    5.1) approve & deposit initial margin to Aave (this can be added to operations, we just have not had the time for that)
     *    5.2) permission settler to be able to borrow from Aave on signer's behalf (this can be a permit and added to pre-interaction)
     * 6) The filler defines the calldata
     *    6.1) create custom fill operation with uniswap V3 routing, can also be 1inch path-finder execution ;)) - we assume that the filler has no inventory
     *    6.2) create taker traits that point to the extension and custon fill operation
     *    6.3) execute `flashLoanFill` on our settlement contract
     * 7) Prove that the position was created via asserts
     */
    function test_flash_fill() external {
        VmSafe.Wallet memory wallet = vm.createWallet("signer");
        uint256 signerPrivateKey = wallet.privateKey;
        address signerAddress = wallet.addr;

        wallet = vm.createWallet("filler");
        address fillerAddress = wallet.addr;

        vm.label(signerAddress, "signerAddress");
        vm.label(fillerAddress, "fillerAddress");

        /**
         * @notice config to use
         * Edit if market conditions change - as we need Uniswap V3 to be able to attain the defined swap rate or better for filling
         */
        UserOrderDefinition memory trade = UserOrderDefinition({
            borrowAsset: USDC,
            collateralAsset: WETH,
            initialMargin: 0.1e18,
            borrowAmount: 360.0e6, // this prices WETH at 3600 USDC - edit if it is too low for market conditions
            depositAmount: 0.1e18
        });

        /** THIS IS WHAT THE USER SIGNER DOES */
        IOrderMixin.Order memory order = _createOrder(trade);

        // the calldata follows this pattern
        // enum DynamicField {
        //     MakerAssetSuffix,
        //     TakerAssetSuffix,
        //     MakingAmountData,
        //     TakingAmountData,
        //     Predicate,
        //     MakerPermit,
        //     PreInteractionData,
        //     PostInteractionData,
        //     CustomData
        // }

        bytes memory extensionCalldata = abi.encodePacked(
            address(marginSettler), // call target in first 20 bytes
            address(signerAddress), // signer in second 20 bytes
            _createOpen(trade.borrowAsset, trade.collateralAsset, AAVE_V3_POOL) // calldata start
        );
        {
            bytes memory offsets = abi.encodePacked(
                uint32(0), // cumulative length MakerAssetSuffix 0 * 32
                uint32(0), // cumulative length TakerAssetSuffix
                uint32(0), // cumulative length MakingAmountData
                uint32(0), // cumulative length TakingAmountData
                uint32(0), // cumulative length Predicate
                uint32(extensionCalldata.length), // cumulative length MakerPermit
                uint32(extensionCalldata.length), // cumulative length PreInteractionData // 7*32
                uint32(extensionCalldata.length) // cumulative length PostInteractionData // 8*32
            );
            // the data needs to be abi coded with offset and length
            extensionCalldata = abi.encodePacked(offsets, extensionCalldata);
        }
        console.logBytes(extensionCalldata);

        deal(WETH, signerAddress, 0.1e18);

        bytes32 extensionHash = marginSettler.hashExtension(extensionCalldata);
        console.logBytes32(extensionHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPrivateKey,
            extensionHash
        );
        bytes memory extensionSignature = abi.encodePacked(r, s, v);

        // bytes memory extensionArgs = extensionCalldata;

        // lower 160 bits are the ext hash
        order.salt =
            (~type(uint160).max & order.salt) |
            (type(uint160).max & uint256(keccak256(extensionCalldata)));
        bytes32 orderHash = marginSettler.hashOrder(order);

        (v, r, s) = vm.sign(signerPrivateKey, orderHash);
        bytes memory orderSignature = abi.encodePacked(r, s, v);

        // approve pool
        vm.prank(signerAddress);
        IERC20(trade.collateralAsset).approve(AAVE_V3_POOL, type(uint).max);

        // deposit margin
        vm.prank(signerAddress);
        IDelegation(AAVE_V3_POOL).supply(
            trade.collateralAsset,
            trade.initialMargin,
            signerAddress,
            0
        );

        // approve borrowing
        vm.prank(signerAddress);
        IDelegation(AAVE_V3_USDC_DEBT).approveDelegation(
            address(marginSettler),
            type(uint).max
        );

        /** THIS IS WHAT THE FILLER DOES */
        {
            // create taker actio n to fill with router
            bytes memory swapCalldata = _createUnoSwapCalldata(
                AddressLib.get(order.makerAsset),
                AddressLib.get(order.takerAsset),
                order.makingAmount
            );

            // attach target
            swapCalldata = abi.encodePacked(
                address(marginSettler),
                swapCalldata
            );

            // create calldata for flash
            swapCalldata = abi.encode(
                order,
                orderSignature,
                order.takingAmount,
                _createTakerTraits(
                    extensionCalldata.length,
                    swapCalldata.length
                ),
                abi.encodePacked(extensionCalldata, swapCalldata),
                extensionSignature
            );
            vm.prank(fillerAddress);
            // fill
            marginSettler.flashLoanFill(
                AddressLib.get(order.takerAsset),
                order.takingAmount,
                abi.encodePacked(fillerAddress, swapCalldata)
            );
        }

        /** VALIDATE THAT POSITION AHS BEEN CREATED */
        uint256 collateralUser = IERC20(AAVE_V3_WETH_COLLATERAL).balanceOf(
            signerAddress
        );
        uint256 debtUser = IERC20(AAVE_V3_USDC_DEBT).balanceOf(signerAddress);

        // asert that the user holds
        // - the takingAmount plus initial margin in collateral
        assertApproxEqRel(
            collateralUser,
            order.takingAmount + trade.initialMargin,
            0.00000001e18
        );

        // - the makingAmount in debt
        assertApproxEqRel(debtUser, order.makingAmount, 0.00000001e18);

        // the asserts expect deviations due to rebasing of debt and collateral tokens
    }
}
