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

/// @notice Simple ETH to Temple swap script for OptimizedTempleHook testing
contract SimpleEthSwapScript is Script, Constants {
    using CurrencyLibrary for Currency;

    function run() external {
        console.log("=== SIMPLE ETH to TEMPLE SWAP ===");
        console.log("Swapper:", msg.sender);

        // Get deployed addresses from environment variables
        address templeToken = vm.envAddress("TEMPLE_TOKEN_ADDRESS");
        address optimizedHook = vm.envAddress("OPTIMIZED_HOOK_ADDRESS");
        
        console.log("Temple Token:", templeToken);
        console.log("OptimizedHook:", optimizedHook);

        // Setup currencies (ETH always sorts before other tokens)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(templeToken); // Temple
        
        // Ensure proper ordering
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.30%
            tickSpacing: 60,
            hooks: IHooks(optimizedHook)
        });

        console.log("Pool Key:");
        console.log("  currency0:", Currency.unwrap(currency0));
        console.log("  currency1:", Currency.unwrap(currency1));

        vm.startBroadcast();

        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("Swap router deployed at:", address(swapRouter));

        // Check balances before swap
        uint256 ethBalanceBefore = msg.sender.balance;
        uint256 templeBalanceBefore = IERC20(templeToken).balanceOf(msg.sender);
        console.log("ETH balance before:", ethBalanceBefore);
        console.log("Temple balance before:", templeBalanceBefore);

        // Swap amount - small amount for testing
        uint256 swapAmount = 0.001 ether; // 0.001 ETH
        console.log("Swapping", swapAmount, "wei for TEMPLE...");

        // Create swap parameters
        bool zeroForOne = Currency.unwrap(currency0) == address(0); // ETH -> Temple
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(swapAmount), // Exact input (negative for exact input)
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap with hook data (user address for donation tracking)
        bytes memory hookData = abi.encode(msg.sender);
        
        try swapRouter.swap{value: swapAmount}(poolKey, swapParams, testSettings, hookData) {
            console.log("SUCCESS: Swap completed with 2% donation to charity!");
            
            // Check balances after swap
            uint256 ethBalanceAfter = msg.sender.balance;
            uint256 templeBalanceAfter = IERC20(templeToken).balanceOf(msg.sender);
            
            console.log("ETH balance after:", ethBalanceAfter);
            console.log("Temple balance after:", templeBalanceAfter);
            
            uint256 ethUsed = ethBalanceBefore - ethBalanceAfter;
            uint256 templeReceived = templeBalanceAfter - templeBalanceBefore;
            
            console.log("ETH used:", ethUsed);
            console.log("Temple received:", templeReceived);
            
            if (ethUsed > 0) {
                console.log("Effective rate: 1 ETH =", (templeReceived * 1e18) / ethUsed, "Temple wei");
            }
            
            // Calculate donation amount (2% of swap)
            uint256 donationAmount = (swapAmount * 20000) / 1000000; // 2% donation
            console.log("Donation to charity:", donationAmount, "wei");
            
        } catch Error(string memory reason) {
            console.log("ERROR: Swap failed -", reason);
        } catch {
            console.log("ERROR: Swap failed - likely insufficient liquidity or hook issue");
        }

        vm.stopBroadcast();
        
        console.log("=== SWAP COMPLETE ===");
    }
}