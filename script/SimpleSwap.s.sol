// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Constants} from "./base/Constants.sol";

/// @notice Simple ETH to T3MPL3 swap script for Temple Hook testing
contract SimpleSwapScript is Script, Constants {
    using CurrencyLibrary for Currency;

    // Contract addresses from environment variables

    function run() external {
        console.log("=== SIMPLE ETH to TEMPLE SWAP ===");
        console.log("Swapper:", msg.sender);
        
        // Get deployed addresses from environment variables
        address templeToken = vm.envAddress("TEMPLE_TOKEN_ADDRESS");
        address optimizedHook = vm.envAddress("OPTIMIZED_HOOK_ADDRESS");
        
        console.log("Temple Token:", templeToken);
        console.log("Temple Hook:", optimizedHook);

        // Setup currencies
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(templeToken); // Temple

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(optimizedHook)
        });

        vm.startBroadcast();

        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("Swap router deployed at:", address(swapRouter));

        // Check balances before swap
        uint256 ethBalanceBefore = msg.sender.balance;
        uint256 templeBalanceBefore = IERC20(templeToken).balanceOf(msg.sender);
        console.log("ETH balance before:", ethBalanceBefore);
        console.log("Temple balance before (raw):", templeBalanceBefore);
        console.log("Temple balance before (display):", templeBalanceBefore / 10**18, "tokens");

        // Swap amount (larger amount for successful settlement)  
        uint256 swapAmount = 0.001 ether; // 0.001 ETH (1000x larger for testing)
        console.log("Swapping", swapAmount, "ETH for Temple...");

        // Create swap parameters (exactInput with negative amount)
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true, // ETH to Temple
            amountSpecified: -int256(swapAmount), // Negative for exactInput
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // No price limit
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap with hook data (user address)
        bytes memory hookData = abi.encode(msg.sender);
        
        try swapRouter.swap{value: swapAmount}(poolKey, swapParams, testSettings, hookData) {
            console.log("SUCCESS: Swap completed!");
            
            // Check balances after swap
            uint256 ethBalanceAfter = msg.sender.balance;
            uint256 templeBalanceAfter = IERC20(templeToken).balanceOf(msg.sender);
            
            console.log("ETH balance after:", ethBalanceAfter);
            console.log("Temple balance after (raw):", templeBalanceAfter);
            console.log("Temple balance after (display):", templeBalanceAfter / 10**18, "tokens");
            
            uint256 ethUsed = ethBalanceBefore - ethBalanceAfter;
            uint256 templeReceived = templeBalanceAfter - templeBalanceBefore;
            
            console.log("=== RAW SWAP RESULTS ===");
            console.log("ETH used (raw wei):", ethUsed);
            console.log("Temple received (raw wei):", templeReceived);
            console.log("Temple received (display):", templeReceived / 10**18, "tokens");
            
            if (templeReceived > 0) {
                console.log("Rate: 1 ETH =", (templeReceived * 1e18) / ethUsed / 10**18, "Temple");
                console.log("TEMPLE TOKENS WERE RECEIVED!");
            } else {
                console.log("NO TEMPLE TOKENS RECEIVED");
            }
            
        } catch Error(string memory reason) {
            console.log("ERROR: Swap failed with reason:", reason);
        } catch {
            console.log("ERROR: Swap failed - likely insufficient liquidity");
            console.log("Try a larger swap amount or add more liquidity to the pool");
        }

        vm.stopBroadcast();
        
        console.log("=== SWAP COMPLETE ===");
    }
}