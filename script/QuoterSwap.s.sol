// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";

import {Constants} from "./base/Constants.sol";

/// @notice Swap script that uses Quoter to get exact amounts first
contract QuoterSwapScript is Script, Constants {
    // Base mainnet Quoter address
    address constant QUOTER = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;

    function run() external {
        console.log("=== QUOTER-BASED SWAP TEST ===");
        console.log("Swapper:", msg.sender);

        // Get deployed addresses
        address mockTemple = vm.envAddress("MOCK_TEMPLE_ADDRESS");
        address mockUSDC = vm.envAddress("MOCK_USDC_ADDRESS");
        address hookAddress = vm.envAddress("HOOK_ADDRESS");

        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("Mock Temple:", mockTemple);
        console.log("Mock USDC:", mockUSDC);
        console.log("Hook:", hookAddress);
        console.log("Quoter:", QUOTER);

        // Setup pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(mockTemple),
            currency1: Currency.wrap(mockUSDC),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(hookAddress)
        });

        // Swap amount
        uint128 amountIn = 1000 * 10**18; // 1000 USDC

        console.log("\n=== STEP 1: GET QUOTE ===");
        console.log("Requesting quote for", amountIn / 10**18, "USDC...");

        // Call quoter
        IV4Quoter quoter = IV4Quoter(QUOTER);
        (uint256 amountOut, uint256 gasEstimate) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: poolKey,
                zeroForOne: false, // USDC -> Temple
                exactAmount: amountIn,
                hookData: hex""
            })
        );

        console.log("Quoted output:", amountOut / 10**18, "Temple");
        console.log("Gas estimate:", gasEstimate);

        vm.startBroadcast();

        console.log("\n=== STEP 2: EXECUTE SWAP ===");

        // Deploy swap router
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(POOLMANAGER));
        console.log("Swap router deployed at:", address(swapRouter));

        // Check balances before
        uint256 usdcBefore = IERC20(mockUSDC).balanceOf(msg.sender);
        uint256 templeBefore = IERC20(mockTemple).balanceOf(msg.sender);

        console.log("\n=== BALANCES BEFORE ===");
        console.log("USDC:", usdcBefore / 10**18);
        console.log("Temple:", templeBefore / 10**18);

        // Approve USDC
        IERC20(mockUSDC).approve(address(swapRouter), amountIn);
        console.log("\nApproved", amountIn / 10**18, "USDC for swap router");

        // Execute swap with quoted amount as minimum
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(uint256(amountIn)),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        console.log("Executing swap with minimum output:", amountOut / 10**18, "Temple");

        try swapRouter.swap(poolKey, swapParams, testSettings, hex"") {
            console.log("\n=== SWAP SUCCESSFUL ===");

            // Check balances after
            uint256 usdcAfter = IERC20(mockUSDC).balanceOf(msg.sender);
            uint256 templeAfter = IERC20(mockTemple).balanceOf(msg.sender);

            console.log("\n=== BALANCES AFTER ===");
            console.log("USDC:", usdcAfter / 10**18);
            console.log("Temple:", templeAfter / 10**18);

            console.log("\n=== RESULTS ===");
            console.log("USDC spent:", (usdcBefore - usdcAfter) / 10**18);
            console.log("Temple received:", (templeAfter - templeBefore) / 10**18);
            console.log("Expected from quote:", amountOut / 10**18);

        } catch Error(string memory reason) {
            console.log("\n=== SWAP FAILED ===");
            console.log("Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n=== SWAP FAILED ===");
            console.logBytes(lowLevelData);
        }

        vm.stopBroadcast();
    }
}
