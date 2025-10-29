// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @title Configurable ERC20 Token
/// @notice Simple ERC20 token with configurable name and symbol
contract ConfigurableToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {
        // Mint 10 billion tokens to deployer
        _mint(msg.sender, 10_000_000_000 * 10**18);
    }
}

/// @notice Deploys a token with configurable name and symbol
/// @dev Use environment variables: TOKEN_NAME and TOKEN_SYMBOL
///      Defaults: "Temple Token" and "TEMPLE"
contract DeployTokenScript is Script {
    function run() external {
        // Get token name from environment or use default
        string memory tokenName;
        try vm.envString("TOKEN_NAME") returns (string memory name) {
            tokenName = name;
        } catch {
            tokenName = "Temple Token";
        }

        // Get token symbol from environment or use default
        string memory tokenSymbol;
        try vm.envString("TOKEN_SYMBOL") returns (string memory symbol) {
            tokenSymbol = symbol;
        } catch {
            tokenSymbol = "TEMPLE";
        }

        console.log("=== DEPLOYING TOKEN ===");
        console.log("Deployer:", msg.sender);
        console.log("Name:", tokenName);
        console.log("Symbol:", tokenSymbol);

        vm.startBroadcast();

        ConfigurableToken token = new ConfigurableToken(tokenName, tokenSymbol);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("Token deployed at:", address(token));
        console.log("Name:", token.name());
        console.log("Symbol:", token.symbol());
        console.log("Decimals:", token.decimals());
        console.log("Total supply:", token.totalSupply() / 10**18);
        console.log("Deployer balance:", token.balanceOf(msg.sender) / 10**18);
        console.log("Supply in billions:", token.totalSupply() / 10**27, "billion");

        console.log("\n=== EXPORT ADDRESS ===");
        console.log("export TOKEN_ADDRESS=", address(token));
    }
}