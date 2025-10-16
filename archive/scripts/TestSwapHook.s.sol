// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract TestSwapScript is Script {
    function run() external {
        console.log("=== TESTING TEMPLE HOOK SWAP ===");
        console.log("Swapping 0.001 ETH for Temple tokens...");
        
        PoolSwapTest swapRouter = PoolSwapTest(0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe);
        
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH
            currency1: Currency.wrap(0xE6BBfB40bAFe0Ec62eB687d5681C920B5d15FD17), // Temple Token
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(0x092B9388Eea97444999C5fc6606eFF3d4CC000C8) // SimpleTempleHook
        });
        
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true, // ETH -> Temple
            amountSpecified: -1000000000000000, // 0.001 ETH (exactInput)
            sqrtPriceLimitX96: 4295128740 // Reasonable price limit to avoid bounds error
        });
        
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        
        // Include sender address in hook data for donation attribution
        bytes memory hookData = abi.encode(msg.sender);
        
        console.log("Pool details:");
        console.log("  ETH:", Currency.unwrap(poolKey.currency0));
        console.log("  Temple:", Currency.unwrap(poolKey.currency1));
        console.log("  Hook:", address(poolKey.hooks));
        console.log("  User:", msg.sender);
        console.log("");
        
        // Check balances before swap
        console.log("=== BEFORE SWAP ===");
        console.log("User ETH balance:", msg.sender.balance);
        console.log("QUBIT charity balance:", 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720.balance);
        
        vm.broadcast();
        swapRouter.swap{value: 0.001 ether}(poolKey, params, settings, hookData);
        
        console.log("=== SWAP COMPLETED ===");
        console.log("Transaction should include CharitableDonationTaken event");
        console.log("Expected donation: ~0.00001 ETH (0.01% of 0.001 ETH)");
        console.log("");
        console.log("Check transaction logs for donation event!");
    }
}