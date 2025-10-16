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

    // Contract addresses from environment variables

    function run() external {
        console.log("=== CREATING ETH/TEMPLE POOL WITH LIQUIDITY ===");
        console.log("ETH amount:", ethAmount);
        console.log("Temple amount:", t3mpl3Amount / 10**18, "tokens");
        
        // Get deployed addresses from environment variables
        address templeToken = vm.envAddress("TEMPLE_TOKEN_ADDRESS");
        address optimizedHook = vm.envAddress("OPTIMIZED_HOOK_ADDRESS");
        
        console.log("Temple token:", templeToken);
        console.log("Hook address:", optimizedHook);

        // Setup currencies (ETH always sorts before other tokens)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(templeToken); // Temple

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(optimizedHook)
        });

        console.log("Pool Key:");
        console.log("  currency0 (ETH):", Currency.unwrap(currency0));
        console.log("  currency1 (Temple):", Currency.unwrap(currency1));
        console.log("  fee:", lpFee);
        console.log("  tickSpacing:", uint256(uint24(tickSpacing)));

        vm.startBroadcast();

        // Step 1: Deploy liquidity router for adding liquidity
        PoolModifyLiquidityTest lpRouter = new PoolModifyLiquidityTest(IPoolManager(POOLMANAGER));
        console.log("Liquidity router deployed at:", address(lpRouter));

        // Step 2: Pool already exists - just add more liquidity
        console.log("Pool already exists - adding liquidity to existing pool");

        // Step 3: Approve Temple tokens for liquidity router
        IERC20(templeToken).approve(address(lpRouter), t3mpl3Amount);
        console.log("Temple tokens approved for liquidity router");

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
        console.log("Pool created with OptimizedTempleHook");
        console.log("Liquidity added: 0.01 ETH + 100K Temple tokens");
        console.log("Pool is ready for swaps!");
        
        // Display pool information
        console.log("\n=== POOL INFORMATION ===");
        console.log("PoolManager:", address(POOLMANAGER));
        console.log("LiquidityRouter:", address(lpRouter));
        console.log("Temple Token:", templeToken);
        console.log("OptimizedTempleHook:", optimizedHook);
    }
}