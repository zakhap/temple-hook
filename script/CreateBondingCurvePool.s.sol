// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

import {Constants} from "./base/Constants.sol";

/// @notice Creates one-sided bonding curve ETH/Temple pool with OptimizedTempleHook
/// @dev Uses Clanker's "Project" multi-position strategy for progressive price discovery
contract CreateBondingCurvePoolScript is Script, Constants {
    using CurrencyLibrary for Currency;

    // USDC address on Base
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Pool configuration
    uint24 lpFee = 3000; // 0.30%
    int24 tickSpacing = 200; // Match Clanker's tick spacing

    // Starting tick: -230400 (standard Clanker starting point)
    // At this tick: 1 Temple = ~$0.000027 USDC (very cheap!)
    int24 startingTick = -230400;
    uint160 startingPrice = TickMath.getSqrtPriceAtTick(startingTick);

    // Total Temple tokens to distribute across all positions
    uint256 totalTempleAmount = 10_000_000_000 * 10**18; // 10B Temple tokens

    function run() external {
        console.log("=== CREATING BONDING CURVE TEMPLE/USDC POOL ===");
        console.log("Strategy: Clanker 'Project' Multi-Position Bonding Curve");
        console.log("Total Temple Supply:", totalTempleAmount / 10**18, "tokens");

        // Get deployed addresses from environment variables
        address templeToken = vm.envAddress("TEMPLE_TOKEN_ADDRESS");
        address optimizedHook = vm.envAddress("OPTIMIZED_HOOK_ADDRESS");

        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("Temple Token:", templeToken);
        console.log("OptimizedHook:", optimizedHook);
        console.log("PoolManager:", address(POOLMANAGER));
        console.log("PositionManager:", address(posm));

        // Setup currencies - Temple as currency0 for one-sided bonding curve
        Currency currency0 = Currency.wrap(templeToken); // Temple
        Currency currency1 = Currency.wrap(USDC); // USDC

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(optimizedHook)
        });

        console.log("\n=== POOL KEY ===");
        console.log("Currency0 (Temple):", Currency.unwrap(currency0));
        console.log("Currency1 (USDC):", Currency.unwrap(currency1));

        vm.startBroadcast();

        // Initialize the pool at starting price
        console.log("\n=== INITIALIZING POOL ===");
        IPoolManager(POOLMANAGER).initialize(poolKey, startingPrice);
        console.log("Pool initialized!");

        // Approve entire Temple supply for PositionManager via Permit2
        IERC20(templeToken).approve(address(PERMIT2), totalTempleAmount);
        PERMIT2.approve(
            templeToken,
            address(posm),
            uint160(totalTempleAmount),
            uint48(block.timestamp + 365 days)
        );
        console.log("Approved Temple tokens for PositionManager");

        // Build actions and params for 5 positions
        bytes memory actions = "";
        bytes[] memory params = new bytes[](6); // 5 positions + 1 SETTLE_PAIR

        // Position 1: 10% of supply, $27K-$130K market cap range
        console.log("\n=== Position 1: 10% (1B tokens) ===");
        uint256 amount1 = (totalTempleAmount * 1000) / 10000; // 1B tokens
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-230400),
            TickMath.getSqrtPriceAtTick(-214000),
            amount1,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[0] = abi.encode(poolKey, -230400, -214000, liquidity1, amount1, 0, msg.sender, abi.encode(""));

        // Position 2: 50% of supply, $130K-$50M market cap range
        console.log("=== Position 2: 50% (5B tokens) ===");
        uint256 amount2 = (totalTempleAmount * 5000) / 10000; // 5B tokens
        uint128 liquidity2 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-214000),
            TickMath.getSqrtPriceAtTick(-155000),
            amount2,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[1] = abi.encode(poolKey, -214000, -155000, liquidity2, amount2, 0, msg.sender, abi.encode(""));

        // Position 3: 15% of supply, $450K-$50M market cap range
        console.log("=== Position 3: 15% (1.5B tokens) ===");
        uint256 amount3 = (totalTempleAmount * 1500) / 10000; // 1.5B tokens
        uint128 liquidity3 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-202000),
            TickMath.getSqrtPriceAtTick(-155000),
            amount3,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[2] = abi.encode(poolKey, -202000, -155000, liquidity3, amount3, 0, msg.sender, abi.encode(""));

        // Position 4: 20% of supply, $50M-$1.5B market cap range
        console.log("=== Position 4: 20% (2B tokens) ===");
        uint256 amount4 = (totalTempleAmount * 2000) / 10000; // 2B tokens
        uint128 liquidity4 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-155000),
            TickMath.getSqrtPriceAtTick(-120000),
            amount4,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[3] = abi.encode(poolKey, -155000, -120000, liquidity4, amount4, 0, msg.sender, abi.encode(""));

        // Position 5: 5% of supply, $200M-$1.5B market cap range
        console.log("=== Position 5: 5% (500M tokens) ===");
        uint256 amount5 = (totalTempleAmount * 500) / 10000; // 500M tokens
        uint128 liquidity5 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-141000),
            TickMath.getSqrtPriceAtTick(-120000),
            amount5,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[4] = abi.encode(poolKey, -141000, -120000, liquidity5, amount5, 0, msg.sender, abi.encode(""));

        // Add SETTLE_PAIR action to finalize token transfers
        actions = abi.encodePacked(actions, uint8(Actions.SETTLE_PAIR));
        params[5] = abi.encode(currency0, currency1);

        console.log("\n=== EXECUTING MULTI-POSITION MINT ===");
        uint256 firstPositionId = posm.nextTokenId();

        // Execute all position mints atomically (NO USDC sent, value = 0)
        posm.modifyLiquidities{value: 0}(
            abi.encode(actions, params),
            block.timestamp + 365 days
        );

        console.log("\n=== BONDING CURVE CREATED ===");
        console.log("Position NFT IDs:", firstPositionId, "through", firstPositionId + 4);

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Pool Type: ONE-SIDED BONDING CURVE (Temple/USDC)");
        console.log("Liquidity: 10B Temple tokens (ZERO USDC)");
        console.log("Positions: 5 concentrated ranges");
        console.log("\n=== READY FOR PRICE DISCOVERY ===");
        console.log("Users buy Temple with USDC, price moves up through the curve!");
    }
}
