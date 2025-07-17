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

/// @notice Test swap with OptimizedTempleHook donation collection
contract TestSwapScript is Script, Constants {
    using CurrencyLibrary for Currency;

    function run() external {
        console.log("=== TESTING SWAP WITH OPTIMIZED HOOK ===");
        
        // Get addresses from environment
        address templeToken = vm.envAddress("TEMPLE_TOKEN_ADDRESS");
        address optimizedHook = vm.envAddress("OPTIMIZED_HOOK_ADDRESS");
        
        console.log("Temple token:", templeToken);
        console.log("OptimizedHook:", optimizedHook);

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

        console.log("Swapper:", msg.sender);

        vm.startBroadcast();

        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("Swap router deployed at:", address(swapRouter));

        // Check initial charity balance
        address charity = address(0x59cf1Fbe6AD1EBf1a01e78EE808B7c889E6dd58A); // From hook deployment
        uint256 initialCharityEthBalance = charity.balance;
        uint256 initialCharityTempleBalance = IERC20(templeToken).balanceOf(charity);
        
        console.log("Initial charity ETH balance:", initialCharityEthBalance);
        console.log("Initial charity Temple balance:", initialCharityTempleBalance);

        // Perform ETH -> Temple swap (0.001 ETH)
        uint256 swapAmount = 0.001 ether;
        console.log("Swapping", swapAmount, "ETH for Temple...");

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true, // ETH -> Temple
            amountSpecified: -int256(swapAmount), // Exact input
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap with hook data (user address)
        bytes memory hookData = abi.encode(msg.sender);
        swapRouter.swap{value: swapAmount}(poolKey, swapParams, testSettings, hookData);

        console.log("Swap completed!");

        // Check charity balances after swap
        uint256 ethDonation = charity.balance - initialCharityEthBalance;
        uint256 templeDonation = IERC20(templeToken).balanceOf(charity) - initialCharityTempleBalance;

        console.log("ETH donation received:", ethDonation);
        console.log("Temple donation received:", templeDonation);

        if (ethDonation > 0) {
            console.log("SUCCESS: Hook collected ETH donation!");
            console.log("Donation rate:", (ethDonation * 1000000) / swapAmount, "/ 1000000");
        } else {
            console.log("No ETH donation detected");
        }

        // Check Temple balance received from swap
        console.log("Temple tokens received:", IERC20(templeToken).balanceOf(msg.sender) / 10**18, "tokens");

        vm.stopBroadcast();

        console.log("\n=== SWAP TEST COMPLETE ===");
        console.log("Hook donation mechanism:", (ethDonation > 0 || templeDonation > 0) ? "WORKING" : "NOT WORKING");
    }
}