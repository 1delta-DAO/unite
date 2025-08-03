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
import {CalldataLib} from "../src/composer/utils/CalldataLib.sol";
import {SweepType} from "../src/composer/lib/enums/MiscEnums.sol";
import {MarginSettlerTest} from "./MarginSettler.t.sol";
import {LendingEncoder} from "./utils/LendingEncoder.sol";

interface IDelegation {
    function approveDelegation(address, uint) external;

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
}

contract SigConstructionTest is MarginSettlerTest {
    uint256 internal constant zero = 0;

    function createOpen(
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

    function test_sig_construct() external {
        VmSafe.Wallet memory wallet = vm.createWallet("signer");
        uint256 signerPrivateKey = wallet.privateKey;
        address signerAddress = wallet.addr;

        IOrderMixin.Order memory order = _createOrder();
        order.receiver = Address.wrap(uint256(uint160(signerAddress)));

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
            // zero, // MakerAssetSuffix
            // zero, // TakerAssetSuffix
            // zero, // MakingAmountData
            // zero, // TakingAmountData
            // zero, // Predicate (makerPermit is 0x)
            address(marginSettler), // PreInteractionData
            createOpen(USDC, WETH, AAVE_V3_POOL)
        );
        {
            bytes memory offsets = abi.encodePacked(
                uint32(0), // start MakerAssetSuffix 0 * 32
                uint32(0), // start TakerAssetSuffix
                uint32(0), // start MakingAmountData
                uint32(0), // start TakingAmountData
                uint32(0), // start Predicate
                uint32(extensionCalldata.length), // start MakerPermit
                uint32(extensionCalldata.length), // start PreInteractionData // 7*32
                uint32(0) // start PostInteractionData // 8*32
            );

            console.log("--- offsets");
            console.logBytes(offsets);
            // the data needs to be abi coded with offset and length
            extensionCalldata = abi.encodePacked(offsets, extensionCalldata);
            console.logBytes(
                marginSettler.preInteractionTargetAndData(extensionCalldata)
            );
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

        console.log("extensionSignature", extensionSignature.length);
        console.log("signerAddress", signerAddress);
        console.log("orderHash");
        console.logBytes32(orderHash);
        console.logBytes(extensionCalldata);

        console.log("-------");
        console.logBytes32(bytes32(type(uint160).max & uint256(extensionHash)));
        console.logBytes32(bytes32(order.salt));
        console.logBytes32(extensionHash);
        console.log(
            "uint256(keccak256(extension)) & type(uint160).max != order.salt & type(uint160).max",
            uint256(keccak256(extensionCalldata)) & type(uint160).max !=
                order.salt & type(uint160).max
        );
        console.log("-------");
        // {
        //         TakerTraits takerTraits = _createTakerTraits(extensionCalldata.length, 0);
        // console.log(TakerTraitsLib.usePermit2(takerTraits));
        // }
        // test calls
        // {
        //     (, bytes memory a, bytes memory b) = marginSettler._parseArgs(
        //         _createTakerTraits(extensionCalldata.length, 0),
        //         extensionCalldata
        //     );
        //     console.logBytes(b);

        //     console.logBytes(marginSettler.takerAssetSuffix(a));
        // }
        // marginSettler.preInteractionTargetAndData(a);
        // console.logBytes(extensionCalldata);
        // vm.expectRevert(0x398d4d32);
        // marginSettler.takeOrder(
        //     order,
        //     orderSignature,
        //     order.takingAmount,
        //     takerTraits,
        //     extensionCalldata
        // );

        // approve pool
        vm.prank(signerAddress);
        IERC20(WETH).approve(AAVE_V3_POOL, type(uint).max);

        // deposit margin
        vm.prank(signerAddress);
        IDelegation(AAVE_V3_POOL).supply(WETH, 0.1e18, signerAddress, 0);

        // approve borrowing
        vm.prank(signerAddress);
        IDelegation(AAVE_V3_USDC_DEBT).approveDelegation(
            address(marginSettler),
            type(uint).max
        );

        {

            // create taker actio n to fill with router
            bytes memory swapCalldata = _createUnoSwapCalldata(
                AddressLib.get(order.makerAsset),
                AddressLib.get(order.takerAsset),
                order.makingAmount
            );

            // attach target
            swapCalldata = abi.encodePacked(address(marginSettler), swapCalldata);

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

            // fill
            marginSettler.flashLoanFill(
                AddressLib.get(order.takerAsset),
                order.takingAmount,
                swapCalldata
            );
        }
    }
}
