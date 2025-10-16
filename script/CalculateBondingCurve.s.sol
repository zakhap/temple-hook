// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

/// @notice Calculate USDC required to buy through each position of the bonding curve
contract CalculateBondingCurveScript is Script {

    // Starting tick: -230400 (standard Clanker starting point)
    int24 startingTick = -230400;
    uint160 startingPrice;

    // Total Temple tokens to distribute across all positions
    uint256 totalTempleAmount = 10_000_000_000 * 10**18; // 10B Temple tokens

    constructor() {
        startingPrice = TickMath.getSqrtPriceAtTick(startingTick);
    }

    function run() external view {
        console.log("=== BONDING CURVE USDC REQUIREMENTS ===\n");

        // Position 1: 10% of supply, tick -230400 to -214000
        console.log("Position 1: 1B Temple (10%)");
        console.log("  Tick range: -230400 to -214000");
        uint256 amount1 = (totalTempleAmount * 1000) / 10000; // 1B tokens
        uint256 usdc1 = calculateUSDCRequired(-230400, -214000, amount1);
        console.log("  Temple tokens:", amount1 / 10**18);
        console.log("  USDC required: $", usdc1 / 10**6);
        console.log("  Average price: $", (usdc1 * 10**12) / amount1, "per Temple");
        console.log("");

        // Position 2: 50% of supply, tick -214000 to -155000
        console.log("Position 2: 5B Temple (50%)");
        console.log("  Tick range: -214000 to -155000");
        uint256 amount2 = (totalTempleAmount * 5000) / 10000; // 5B tokens
        uint256 usdc2 = calculateUSDCRequired(-214000, -155000, amount2);
        console.log("  Temple tokens:", amount2 / 10**18);
        console.log("  USDC required: $", usdc2 / 10**6);
        console.log("  Average price: $", (usdc2 * 10**12) / amount2, "per Temple");
        console.log("  Cumulative USDC: $", (usdc1 + usdc2) / 10**6);
        console.log("");

        // Position 3: 15% of supply, tick -202000 to -155000
        console.log("Position 3: 1.5B Temple (15%)");
        console.log("  Tick range: -202000 to -155000");
        uint256 amount3 = (totalTempleAmount * 1500) / 10000; // 1.5B tokens
        uint256 usdc3 = calculateUSDCRequired(-202000, -155000, amount3);
        console.log("  Temple tokens:", amount3 / 10**18);
        console.log("  USDC required: $", usdc3 / 10**6);
        console.log("  Average price: $", (usdc3 * 10**12) / amount3, "per Temple");
        console.log("  Cumulative USDC: $", (usdc1 + usdc2 + usdc3) / 10**6);
        console.log("");

        // Position 4: 20% of supply, tick -155000 to -120000
        console.log("Position 4: 2B Temple (20%)");
        console.log("  Tick range: -155000 to -120000");
        uint256 amount4 = (totalTempleAmount * 2000) / 10000; // 2B tokens
        uint256 usdc4 = calculateUSDCRequired(-155000, -120000, amount4);
        console.log("  Temple tokens:", amount4 / 10**18);
        console.log("  USDC required: $", usdc4 / 10**6);
        console.log("  Average price: $", (usdc4 * 10**12) / amount4, "per Temple");
        console.log("  Cumulative USDC: $", (usdc1 + usdc2 + usdc3 + usdc4) / 10**6);
        console.log("");

        // Position 5: 5% of supply, tick -141000 to -120000
        console.log("Position 5: 500M Temple (5%)");
        console.log("  Tick range: -141000 to -120000");
        uint256 amount5 = (totalTempleAmount * 500) / 10000; // 500M tokens
        uint256 usdc5 = calculateUSDCRequired(-141000, -120000, amount5);
        console.log("  Temple tokens:", amount5 / 10**18);
        console.log("  USDC required: $", usdc5 / 10**6);
        console.log("  Average price: $", (usdc5 * 10**12) / amount5, "per Temple");
        console.log("");

        uint256 totalUSDC = usdc1 + usdc2 + usdc3 + usdc4 + usdc5;
        console.log("=== TOTAL BONDING CURVE ===");
        console.log("Total USDC to buy all 10B Temple: $", totalUSDC / 10**6);
        console.log("Overall average price: $", (totalUSDC * 10**12) / totalTempleAmount, "per Temple");
        console.log("Final price at end of curve: ~$0.15 per Temple");
    }

    /// @notice Calculate USDC required to buy all Temple tokens in a tick range
    /// @dev For one-sided liquidity where we start with all Temple (token0):
    /// We calculate the liquidity L from the Temple amount, then get USDC amount from L
    function calculateUSDCRequired(
        int24 tickLower,
        int24 tickUpper,
        uint256 templeAmount
    ) internal view returns (uint256 usdcRequired) {
        // Get sqrt prices at tick boundaries (Q64.96 format)
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // Calculate liquidity from Temple amount using Uniswap's library
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,  // Current price (at tickLower)
            sqrtPriceLower,
            sqrtPriceUpper,
            templeAmount,   // Temple is amount0
            0               // USDC is amount1 (zero for one-sided)
        );

        // Now calculate how much USDC is needed to exhaust this liquidity
        // When we swap from tickLower to tickUpper, we need:
        // amount1 = L * (sqrtPU - sqrtPL)
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceUpper,  // After swap, price is at upper tick
            sqrtPriceLower,
            sqrtPriceUpper,
            liquidity
        );

        // amount1 is the USDC required to buy all the Temple
        usdcRequired = amount1;

        return usdcRequired;
    }
}
