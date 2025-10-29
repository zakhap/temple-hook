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

/// @notice Test swap with Mock USDC to buy Mock Temple tokens
/// @dev Verifies charitable donation mechanism on Base mainnet
contract TestMockSwapScript is Script, Constants {
    using CurrencyLibrary for Currency;

    function run() external {
        console.log("=== TEST MOCK USDC -> MOCK TEMPLE SWAP ===");
        console.log("Swapper:", msg.sender);

        // Get deployed addresses from environment variables
        address mockTemple = vm.envAddress("MOCK_TEMPLE6_ADDRESS");
        address mockUSDC = vm.envAddress("MOCK_USDC6_ADDRESS");
        address hookAddress = vm.envAddress("SIMPLE_HOOK_V2_ADDRESS");

        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("Mock Temple:", mockTemple);
        console.log("Mock USDC:", mockUSDC);
        console.log("Hook:", hookAddress);
        console.log("PoolManager:", address(POOLMANAGER));

        // Setup currencies (must match pool creation order)
        Currency currency0 = Currency.wrap(mockTemple); // Temple
        Currency currency1 = Currency.wrap(mockUSDC);   // USDC

        // Create pool key (must match exactly with pool creation)
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0,           // 0% LP fees
            tickSpacing: 200, // Match bonding curve
            hooks: IHooks(hookAddress)
        });

        vm.startBroadcast();

        // Deploy swap router (required for testing swaps)
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("\n=== SWAP ROUTER ===");
        console.log("Deployed at:", address(swapRouter));

        // Check balances before swap
        uint256 usdcBefore = IERC20(mockUSDC).balanceOf(msg.sender);
        uint256 templeBefore = IERC20(mockTemple).balanceOf(msg.sender);

        console.log("\n=== BALANCES BEFORE SWAP ===");
        console.log("Mock USDC:", usdcBefore / 10**18, "tokens");
        console.log("Mock Temple:", templeBefore / 10**18, "tokens");

        // Swap amount: 10,000 USDC worth of tokens
        uint256 swapAmount = 10000 * 10**18; // 10,000 USDC

        // Approve extra to cover donation (hook takes 5% = 5000/100000)
        // We need to approve enough for both the swap AND the donation
        uint256 approvalAmount = swapAmount * 110 / 100; // 10% buffer to be safe

        console.log("\n=== EXECUTING SWAP ===");
        console.log("Swapping", swapAmount / 10**18, "mUSDC for mTEMPLE...");
        console.log("Approving", approvalAmount / 10**18, "mUSDC (includes buffer for donation)");

        // Approve USDC for swap router with buffer
        IERC20(mockUSDC).approve(address(swapRouter), approvalAmount);
        console.log("Approved mUSDC for swap router");

        // Create swap parameters
        // zeroForOne = false means we're swapping currency1 (USDC) for currency0 (Temple)
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,              // USDC -> Temple (swapping currency1 for currency0)
            amountSpecified: -int256(swapAmount), // Negative for exactInput
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1 // No price limit
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap
        bytes memory hookData = abi.encode(msg.sender);

        try swapRouter.swap(poolKey, swapParams, testSettings, hookData) {
            console.log("\n=== SWAP SUCCESSFUL ===");

            // Check balances after swap
            uint256 usdcAfter = IERC20(mockUSDC).balanceOf(msg.sender);
            uint256 templeAfter = IERC20(mockTemple).balanceOf(msg.sender);

            console.log("\n=== BALANCES AFTER SWAP ===");
            console.log("Mock USDC:", usdcAfter / 10**18, "tokens");
            console.log("Mock Temple:", templeAfter / 10**18, "tokens");

            uint256 usdcSpent = usdcBefore - usdcAfter;
            uint256 templeReceived = templeAfter - templeBefore;

            console.log("\n=== SWAP RESULTS ===");
            console.log("mUSDC spent:", usdcSpent / 10**18, "tokens");
            console.log("mTEMPLE received:", templeReceived / 10**18, "tokens");

            if (templeReceived > 0) {
                uint256 pricePerTemple = (usdcSpent * 1e18) / templeReceived;
                console.log("Price per mTEMPLE:", pricePerTemple / 10**18, "mUSDC");
                console.log("\n=== SUCCESS: TOKENS RECEIVED ===");
            } else {
                console.log("\nWARNING: No Temple tokens received");
            }

        } catch Error(string memory reason) {
            console.log("\n=== SWAP FAILED ===");
            console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n=== SWAP FAILED (Low-level error) ===");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();

        console.log("\n=== TEST COMPLETE ===");
    }
}
