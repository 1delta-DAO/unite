// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MarginSettler} from "../src/settler/MarginSettler.sol";

contract DeployMarginSettler is Script {
    // Arbitrum addresses
    address constant LIMIT_ORDER_PROTOCOL =
        0x54431918cEC22932fCF208e2EaaF1339B3628177;
    address constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant UNISWAP_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying MarginSettler with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MarginSettler
        MarginSettler marginSettler = new MarginSettler(
            LIMIT_ORDER_PROTOCOL,
            AAVE_V3_POOL,
            UNISWAP_V3_ROUTER
        );

        console.log("MarginSettler deployed at:", address(marginSettler));

        vm.stopBroadcast();

        // Verify deployment
        console.log("Verifying deployment...");
        console.log(
            "Limit Order Protocol:",
            marginSettler.LIMIT_ORDER_PROTOCOL()
        );
        console.log("Aave V3 Pool:", marginSettler.AAVE_V3_POOL());
        console.log("Uniswap V3 Router:", marginSettler.UNISWAP_V3_ROUTER());

        // Log deployment information
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Network: Arbitrum");
        console.log("MarginSettler Address:", address(marginSettler));
        console.log("Block Number:", block.number);
        console.log("Gas Used: Check transaction receipt");

        console.log("\n=== NEXT STEPS ===");
        console.log("1. Update frontend environment variables");
        console.log("2. Verify contract on Arbiscan");
        console.log("3. Test basic functionality");
        console.log("4. Configure monitoring");
    }
}
