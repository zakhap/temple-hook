// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

import {Constants} from "./base/Constants.sol";

/// @notice Creates ETH/T3MPL3 pool with SimpleTempleHook and adds all liquidity
contract CreatePoolWithLiquidityScript is Script, Constants {
    using CurrencyLibrary for Currency;

    // Pool configuration
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 79228162514264337593543950336; // sqrt(1) * 2^96 = 1:1 price

    // SUBSTANTIAL LIQUIDITY: 0.01 ETH + 100K T3MPL3 tokens for functional swaps
    uint256 ethAmount = 0.01 ether;
    uint256 t3mpl3Amount = 100_000 * 10**18; // 100K tokens (substantial liquidity)

    // Full range liquidity
    int24 tickLower = TickMath.minUsableTick(tickSpacing);
    int24 tickUpper = TickMath.maxUsableTick(tickSpacing);

    // Contract addresses (SEPOLIA DEPLOYMENT)
    address constant T3MPL3_TOKEN = 0x4f4a372fb9635e555Aa2Ede24C3b32740fb7bF39;
    address constant SIMPLE_TEMPLE_HOOK = 0x30162ab2ad00a57Ce848A3d8F8Df5aE8f8aF4088;

    function run() external {
        console.log("=== CREATING ETH/T3MPL3 POOL WITH LIQUIDITY ===");
        console.log("ETH amount:", ethAmount);
        console.log("T3MPL3 amount:", t3mpl3Amount / 10**18, "tokens");
        console.log("Hook address:", SIMPLE_TEMPLE_HOOK);

        // Setup currencies (ETH always sorts before other tokens)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(T3MPL3_TOKEN); // T3MPL3

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(SIMPLE_TEMPLE_HOOK)
        });

        console.log("Pool Key:");
        console.log("  currency0 (ETH):", Currency.unwrap(currency0));
        console.log("  currency1 (T3MPL3):", Currency.unwrap(currency1));
        console.log("  fee:", lpFee);
        console.log("  tickSpacing:", uint256(uint24(tickSpacing)));

        vm.startBroadcast();

        // Step 1: Deploy liquidity router for adding liquidity
        PoolModifyLiquidityTest lpRouter = new PoolModifyLiquidityTest(IPoolManager(POOLMANAGER));
        console.log("Liquidity router deployed at:", address(lpRouter));

        // Step 2: Pool already exists - just add more liquidity
        console.log("Pool already exists - adding liquidity to existing pool");

        // Step 3: Approve T3MPL3 tokens for liquidity router
        IERC20(T3MPL3_TOKEN).approve(address(lpRouter), t3mpl3Amount);
        console.log("T3MPL3 tokens approved for liquidity router");

        // Step 4: Calculate proper liquidity delta based on token amounts
        // Use LiquidityAmounts library to get correct liquidity for our token amounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            ethAmount,      // 0.01 ETH
            t3mpl3Amount    // 100K T3MPL3 tokens
        );
        
        IPoolManager.ModifyLiquidityParams memory liqParams = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(uint256(liquidity)), // Properly calculated liquidity delta
            salt: 0
        });

        console.log("Adding liquidity...");
        console.log("  Tick range:", uint256(uint24(tickLower)), "to", uint256(uint24(tickUpper)));
        console.log("  Liquidity delta:", uint256(liqParams.liquidityDelta));

        // Add liquidity with ETH value
        lpRouter.modifyLiquidity{value: ethAmount}(poolKey, liqParams, "");

        vm.stopBroadcast();

        console.log("=== POOL CREATION COMPLETE ===");
        console.log("Pool created with SimpleTempleHook");
        console.log("Liquidity added: 0.01 ETH + 100K T3MPL3 tokens");
        console.log("Pool is ready for swaps!");
        
        // Display pool information
        console.log("\n=== POOL INFORMATION ===");
        console.log("PoolManager:", address(POOLMANAGER));
        console.log("LiquidityRouter:", address(lpRouter));
        console.log("T3MPL3 Token:", T3MPL3_TOKEN);
        console.log("SimpleTempleHook:", SIMPLE_TEMPLE_HOOK);
    }
}