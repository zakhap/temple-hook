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

/// @notice Tests swap functionality with SimpleTempleHook donation mechanism
contract TestSwapWithDonationScript is Script, Constants {
    using CurrencyLibrary for Currency;

    // Contract addresses (SEPOLIA DEPLOYMENT)
    address constant T3MPL3_TOKEN = 0x4f4a372fb9635e555Aa2Ede24C3b32740fb7bF39;
    address constant SIMPLE_TEMPLE_HOOK = 0x30162ab2ad00a57Ce848A3d8F8Df5aE8f8aF4088;
    address constant QUBIT_CHARITY = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    address constant SEPOLIA_WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    function run() external {
        console.log("=== TESTING SWAP WITH DONATION MECHANISM ===");
        console.log("Swapper:", msg.sender);
        console.log("Hook:", SIMPLE_TEMPLE_HOOK);
        console.log("QUBIT Charity:", QUBIT_CHARITY);

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

        console.log("Pool Key created for ETH/T3MPL3 pair");

        vm.startBroadcast();

        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("Swap router deployed at:", address(swapRouter));

        // Check initial QUBIT charity balance (should be 0)
        uint256 initialCharityBalance = address(QUBIT_CHARITY).balance;
        console.log("Initial QUBIT charity ETH balance:", initialCharityBalance);

        // Perform a nano ETH -> T3MPL3 swap (0.000001 ETH to test donation)
        uint256 swapAmount = 0.000001 ether;
        console.log("Swapping", swapAmount, "ETH for T3MPL3...");

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true, // ETH -> T3MPL3
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1 // No price limit
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap with hook data (user address)
        bytes memory hookData = abi.encode(msg.sender);
        swapRouter.swap{value: swapAmount}(poolKey, swapParams, testSettings, hookData);

        console.log("Swap completed!");

        // Check QUBIT charity balance after swap
        uint256 finalCharityBalance = address(QUBIT_CHARITY).balance;
        uint256 donationReceived = finalCharityBalance - initialCharityBalance;

        console.log("Final QUBIT charity ETH balance:", finalCharityBalance);
        console.log("Donation received:", donationReceived);

        if (donationReceived > 0) {
            console.log("SUCCESS: Hook collected donation!");
            uint256 donationPercentage = (donationReceived * 100000) / swapAmount;
            console.log("Donation percentage:", donationPercentage, "/ 100000");
            console.log("That's", donationPercentage / 10, "basis points");
        } else {
            console.log("WARNING: No donation detected");
        }

        // Check T3MPL3 balance received from swap
        uint256 t3mpl3Balance = IERC20(T3MPL3_TOKEN).balanceOf(msg.sender);
        console.log("T3MPL3 tokens received:", t3mpl3Balance / 10**18, "tokens");

        vm.stopBroadcast();

        console.log("\n=== SWAP TEST COMPLETE ===");
        console.log("Hook donation mechanism:", donationReceived > 0 ? "WORKING" : "NOT WORKING");
        console.log("Swap functionality:", t3mpl3Balance > 0 ? "WORKING" : "NOT WORKING");
    }
}