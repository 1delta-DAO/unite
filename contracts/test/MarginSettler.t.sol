// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {MarginSettler} from "../src/settler/MarginSettler.sol";
import {IOrderMixin} from "@1inch/lo/interfaces/IOrderMixin.sol";
import {MakerTraits, MakerTraitsLib} from "@1inch/lo/libraries/MakerTraitsLib.sol";
import {TakerTraits, TakerTraitsLib} from "@1inch/lo/libraries/TakerTraitsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address, AddressLib} from "@1inch/solidity-utils/contracts/libraries/AddressLib.sol";
import {SweepType} from "../src/composer/lib/enums/MiscEnums.sol";

// @solhint-disable private-vars-leading-underscore

contract MarginSettlerTest is Test {
    bytes32 constant DOMAIN_SEPARATOR =
        0x076055e6d39ad67389e67f0a2296f77935b06fe3fa8764b71089768788c0a53d;

    address constant LIMIT_ORDER_PROTOCOL =
        0x111111125421cA6dc452d289314280a0f8842A65;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant AAVE_V3_WETH = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
    address constant AAVE_v3_WETH_DEBT =
        0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351;
    address constant AAVE_V3_WETH_COLLATERAL =
        0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
    address constant AAVE_V3_USDC = 0x625E7708f30cA75bfd92586e17077590C60eb4cD;
    address constant AAVE_V3_USDC_DEBT =
        0xf611aEb5013fD2c0511c9CD55c7dc5C1140741A6;
    address constant CALL_FORWARDER =
        0xfCa1154C643C32638AEe9a43eeE7f377f515c801;
    address constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_V3_QUOTER =
        0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    MarginSettler public marginSettler;
    address public user;
    uint256 public userPrivateKey;

    struct UserOrderDefinition {
        address borrowAsset;
        address collateralAsset;
        uint256 initialMargin;
        uint256 borrowAmount;
        uint256 depositAmount;
    }

    function setUp() public {
        VmSafe.Wallet memory userWallet = vm.createWallet("user");
        user = userWallet.addr;
        userPrivateKey = userWallet.privateKey;

        marginSettler = new MarginSettler(
            LIMIT_ORDER_PROTOCOL,
            UNISWAP_V3_ROUTER
        );

        vm.label(user, "user");
        vm.label(address(marginSettler), "marginSettler");
        vm.label(LIMIT_ORDER_PROTOCOL, "limitOrderProtocol");
        vm.label(WETH, "weth");
        vm.label(USDC, "usdc");
        vm.label(AAVE_V3_POOL, "aaveV3Pool");
        vm.label(AAVE_V3_WETH, "aaveV3Weth");
        vm.label(AAVE_V3_USDC, "aaveV3Usdc");
        vm.label(CALL_FORWARDER, "CallForwarder");
        vm.label(UNISWAP_V3_FACTORY, "uniswapV3Factory");
        vm.label(UNISWAP_V3_ROUTER, "uniswapV3Router");
        vm.label(UNISWAP_V3_QUOTER, "uniswapV3Quoter");

        vm.createSelectFork("wss://arbitrum-one-rpc.publicnode.com");
    }

    function _createMakerTraits() internal view returns (MakerTraits) {
        uint256 traits = 0;

        // HAS_EXTENSION_FLAG
        traits |= (1 << 249);

        // PRE_INTERACTION_CALL_FLAG
        traits |= (1 << 252);

        // POST_INTERACTION_CALL_FLAG
        traits |= (1 << 251);

        // Set the next 80 bytes to last 10 bytes of the allowed sender
        traits |=
            uint256(
                uint80(uint160(address(marginSettler)) & type(uint80).max)
            ) <<
            120;

        // expiry
        // traits |=
        //     uint256(
        //         uint40(1)
        //     ) <<
        //     80;

        return MakerTraits.wrap(traits);
    }

    function _createTakerTraits(
        uint256 extensionLength,
        uint256 interactionLength
    ) internal pure returns (TakerTraits tt) {
        uint256 traits = 0;

        // ARGS_EXTENSION_LENGTH
        traits |= (extensionLength << 224);

        // ARGS_INTERACTION_LENGTH
        traits |= (interactionLength << 200);

        tt = TakerTraits.wrap(traits);

        return tt;
    }

    function _createOrder(
        UserOrderDefinition memory def
    ) internal view returns (IOrderMixin.Order memory) {
        return
            IOrderMixin.Order({
                salt: uint256(keccak256("testSalt")),
                maker: Address.wrap(uint256(uint160(address(marginSettler)))),
                receiver: Address.wrap(
                    uint256(uint160(address(marginSettler)))
                ),
                takerAsset: Address.wrap(uint256(uint160(def.collateralAsset))),
                makerAsset: Address.wrap(uint256(uint160(def.borrowAsset))),
                takingAmount: def.depositAmount,
                makingAmount: def.borrowAmount,
                makerTraits: _createMakerTraits()
            });
    }

    function _createUnoSwapCalldata(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal view returns (bytes memory) {
        // in taker interaction, we swap the maker token to taker token
        bytes memory extCalldata = abi.encodeWithSelector(
            0x414bf389, // exactInputSingle
            tokenIn,
            tokenOut,
            3000,
            address(marginSettler),
            type(uint).max,
            amount,
            0,
            0
        );
        return extCalldata;
    }
}
