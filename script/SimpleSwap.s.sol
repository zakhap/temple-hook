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

    // Contract addresses (SEPOLIA DEPLOYMENT)
    address constant T3MPL3_TOKEN = 0x4f4a372fb9635e555Aa2Ede24C3b32740fb7bF39;
    address constant SIMPLE_TEMPLE_HOOK = 0x30162ab2ad00a57Ce848A3d8F8Df5aE8f8aF4088;

    function run() external {
        console.log("=== SIMPLE ETH to T3MPL3 SWAP ===");
        console.log("Swapper:", msg.sender);
        console.log("T3MPL3 Token:", T3MPL3_TOKEN);
        console.log("Temple Hook:", SIMPLE_TEMPLE_HOOK);

        // Setup currencies
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(T3MPL3_TOKEN); // T3MPL3

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(SIMPLE_TEMPLE_HOOK)
        });

        vm.startBroadcast();

        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("Swap router deployed at:", address(swapRouter));

        // Check balances before swap
        uint256 ethBalanceBefore = msg.sender.balance;
        uint256 t3mpl3BalanceBefore = IERC20(T3MPL3_TOKEN).balanceOf(msg.sender);
        console.log("ETH balance before:", ethBalanceBefore);
        console.log("T3MPL3 balance before:", t3mpl3BalanceBefore / 10**18, "tokens");

        // Swap amount (adjust as needed)  
        uint256 swapAmount = 0.000001 ether; // 0.000001 ETH (tiny amount for testing)
        console.log("Swapping", swapAmount, "ETH for T3MPL3...");

        // Create swap parameters
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true, // ETH to T3MPL3
            amountSpecified: int256(swapAmount),
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
            uint256 t3mpl3BalanceAfter = IERC20(T3MPL3_TOKEN).balanceOf(msg.sender);
            
            console.log("ETH balance after:", ethBalanceAfter);
            console.log("T3MPL3 balance after:", t3mpl3BalanceAfter / 10**18, "tokens");
            
            uint256 ethUsed = ethBalanceBefore - ethBalanceAfter;
            uint256 t3mpl3Received = t3mpl3BalanceAfter - t3mpl3BalanceBefore;
            
            console.log("ETH used:", ethUsed);
            console.log("T3MPL3 received:", t3mpl3Received / 10**18, "tokens");
            console.log("Rate: 1 ETH =", (t3mpl3Received * 1e18) / ethUsed / 10**18, "T3MPL3");
            
        } catch {
            console.log("ERROR: Swap failed - likely insufficient liquidity");
            console.log("Try a larger swap amount or add more liquidity to the pool");
        }

        vm.stopBroadcast();
        
        console.log("=== SWAP COMPLETE ===");
    }
}