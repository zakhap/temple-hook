// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @title Temple Token for Testing
/// @notice Simple ERC20 token for OptimizedTempleHook testing
contract TempleToken is ERC20 {
    constructor() ERC20("Temple Token", "TEMPLE", 18) {
        // Mint 1 million tokens to deployer
        _mint(msg.sender, 1_000_000 * 10**18);
    }
}

/// @notice Deploys Temple token for testing
contract DeployTempleTokenScript is Script {
    function run() external {
        console.log("=== DEPLOYING TEMPLE TOKEN ===");
        console.log("Deployer:", msg.sender);
        
        vm.startBroadcast();
        
        TempleToken temple = new TempleToken();
        
        vm.stopBroadcast();
        
        console.log("Temple Token deployed at:", address(temple));
        console.log("Total supply:", temple.totalSupply() / 10**18, "TEMPLE");
        console.log("Deployer balance:", temple.balanceOf(msg.sender) / 10**18, "TEMPLE");
        
        console.log("\n=== DEPLOYMENT COMPLETE ===");
    }
}