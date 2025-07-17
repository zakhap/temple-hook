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

/// @notice Creates lopsided ETH/Temple pool with OptimizedTempleHook
contract CreateOptimizedPoolScript is Script, Constants {
    using CurrencyLibrary for Currency;

    // Pool configuration
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 60;
    uint160 startingPrice = 79228162514264337593543950336; // sqrt(1) * 2^96 = 1:1 price

    // LOPSIDED LIQUIDITY: 0.01 ETH + 100,000 Temple tokens
    uint256 ethAmount = 0.01 ether;
    uint256 templeAmount = 100_000 * 10**18; // 100K Temple tokens

    // Full range liquidity
    int24 tickLower = TickMath.minUsableTick(tickSpacing);
    int24 tickUpper = TickMath.maxUsableTick(tickSpacing);

    function run() external {
        console.log("=== CREATING LOPSIDED ETH/TEMPLE POOL ===");
        console.log("ETH amount:", ethAmount);
        console.log("Temple amount:", templeAmount / 10**18, "tokens");

        // Get deployed addresses from previous scripts
        // You'll need to update these addresses after running the deployment scripts
        address templeToken = vm.envAddress("TEMPLE_TOKEN_ADDRESS");
        address optimizedHook = vm.envAddress("OPTIMIZED_HOOK_ADDRESS");
        
        console.log("Temple token:", templeToken);
        console.log("OptimizedHook:", optimizedHook);

        // Setup currencies (ETH always sorts before other tokens)
        Currency currency0 = Currency.wrap(address(0)); // ETH
        Currency currency1 = Currency.wrap(templeToken); // Temple
        
        // Ensure proper ordering
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
            console.log("Swapped currency order for proper sorting");
        }

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(optimizedHook)
        });

        console.log("Pool Key:");
        console.log("  currency0:", Currency.unwrap(currency0));
        console.log("  currency1:", Currency.unwrap(currency1));
        console.log("  fee:", lpFee);
        console.log("  hook:", address(poolKey.hooks));

        vm.startBroadcast();

        // Deploy liquidity router
        PoolModifyLiquidityTest lpRouter = new PoolModifyLiquidityTest(IPoolManager(POOLMANAGER));
        console.log("Liquidity router deployed at:", address(lpRouter));

        // Initialize the pool
        console.log("Initializing pool...");
        IPoolManager(POOLMANAGER).initialize(poolKey, startingPrice);
        console.log("Pool initialized!");

        // Approve Temple tokens for liquidity router
        IERC20(templeToken).approve(address(lpRouter), templeAmount);
        console.log("Temple tokens approved for liquidity router");

        // Calculate liquidity for our token amounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            Currency.unwrap(currency0) == address(0) ? ethAmount : templeAmount,      // amount0
            Currency.unwrap(currency1) == address(0) ? ethAmount : templeAmount       // amount1
        );
        
        IPoolManager.ModifyLiquidityParams memory liqParams = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(uint256(liquidity)),
            salt: 0
        });

        console.log("Adding lopsided liquidity...");
        console.log("  Liquidity delta:", uint256(liqParams.liquidityDelta));

        // Add liquidity with ETH value (if ETH is one of the currencies)
        uint256 ethValue = Currency.unwrap(currency0) == address(0) || Currency.unwrap(currency1) == address(0) ? ethAmount : 0;
        lpRouter.modifyLiquidity{value: ethValue}(poolKey, liqParams, "");

        vm.stopBroadcast();

        console.log("\n=== LOPSIDED POOL CREATION COMPLETE ===");
        console.log("Pool created with OptimizedTempleHook");
        console.log("Lopsided liquidity: 0.01 ETH + 100K Temple tokens");
        console.log("Price will appreciate quickly due to imbalance!");
        
        // Display important addresses
        console.log("\n=== IMPORTANT ADDRESSES ===");
        console.log("PoolManager:", address(POOLMANAGER));
        console.log("LiquidityRouter:", address(lpRouter));
        console.log("Temple Token:", templeToken);
        console.log("OptimizedHook:", optimizedHook);
        
        console.log("\n=== READY FOR SWAPS! ===");
        console.log("The pool is now ready for testing swaps with donations");
    }
}