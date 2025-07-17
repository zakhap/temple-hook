// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {TempleToken} from "../src/TempleToken.sol";

/// @notice Deploys T3MPL3 Token with specified supply
contract DeployT3MPL3TokenScript is Script {
    function run() public returns (address tokenAddress) {
        console.log("=== T3MPL3 TOKEN DEPLOYMENT ===");
        console.log("Deployer:", msg.sender);
        
        // Deploy T3MPL3 token with 1M supply
        uint256 totalSupply = 1_000_000 * 10**18; // 1 million tokens
        
        vm.broadcast();
        TempleToken t3mpl3Token = new TempleToken(
            "Temple Token",
            "T3MPL3", 
            totalSupply
        );
        
        tokenAddress = address(t3mpl3Token);
        
        console.log("T3MPL3 Token deployed at:", tokenAddress);
        console.log("Total supply:", totalSupply / 10**18, "tokens");
        console.log("Deployer balance:", t3mpl3Token.balanceOf(msg.sender) / 10**18, "tokens");
        
        return tokenAddress;
    }
}