// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @notice Quick script to check what prices our ticks represent
contract CheckTickPricesScript is Script {
    function run() external pure {
        console.log("=== TICK PRICES (Temple/USDC) ===\n");

        int24[6] memory ticks = [
            int24(-230400),  // Start
            int24(-214000),  // Pos 1 end
            int24(-202000),  // Pos 3 start
            int24(-155000),  // Pos 2/3 end, Pos 4 start
            int24(-141000),  // Pos 5 start
            int24(-120000)   // Pos 4/5 end
        ];

        for (uint i = 0; i < ticks.length; i++) {
            int24 tick = ticks[i];
            uint160 sqrtPrice = TickMath.getSqrtPriceAtTick(tick);

            // sqrtPrice is in Q64.96, so price = (sqrtPrice / 2^96)^2
            // Price represents USDC per Temple (currency1 per currency0)

            // Convert to readable format
            // price = (sqrtPrice^2) / (2^192)
            uint256 price = mulDiv(uint256(sqrtPrice), uint256(sqrtPrice), 2**96);

            console.log("Tick:", tick);
            console.log("  sqrtPrice:", sqrtPrice);
            console.log("  Price (USDC per Temple, raw):", price);
            console.log("  Temple per USDC:", (2**96) / price);
            console.log("");
        }
    }

    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        require(denominator > prod1);

        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        uint256 twos = (type(uint256).max - denominator + 1) & denominator;
        assembly {
            denominator := div(denominator, twos)
        }

        assembly {
            prod0 := div(prod0, twos)
        }
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
        return result;
    }
}
