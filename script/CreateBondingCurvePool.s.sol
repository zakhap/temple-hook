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

/// @notice Creates one-sided bonding curve Temple/USDC pool with SimpleTempleHook
/// @dev Exponential decay distribution (40/20/12/8/20) reaching $1 in final position
contract CreateBondingCurvePoolScript is Script, Constants {
    using CurrencyLibrary for Currency;

    // USDC address on Base
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Pool configuration
    uint24 lpFee = 0; // 0% LP fees (hook takes 5% donation)
    int24 tickSpacing = 200; // Uniswap v4 tick spacing

    // Starting tick: -92200
    // At this tick: 1 Temple = $0.0001 USDC
    int24 startingTick = -92200;
    uint160 startingPrice = TickMath.getSqrtPriceAtTick(startingTick);

    // Total Temple tokens to distribute across all positions
    uint256 totalTempleAmount = 10_000_000_000 * 10**18; // 10B Temple tokens

    function run() external {
        console.log("=== CREATING BONDING CURVE TEMPLE/USDC POOL ===");
        console.log("Strategy: Exponential Decay with Infinity Pool (40/20/12/8/20)");
        console.log("Total Temple Supply:", totalTempleAmount / 10**18, "tokens");
        console.log("Price Range: $0.0001 -> $1.00 (10,000x appreciation)");

        // Get deployed addresses from environment variables
        address templeToken = vm.envAddress("MOCK_TEMPLE6_ADDRESS");
        address usdcToken = vm.envAddress("MOCK_USDC6_ADDRESS");
        address hookAddress = vm.envAddress("SIMPLE_HOOK_V2_ADDRESS");

        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("Temple Token:", templeToken);
        console.log("USDC Token:", usdcToken);
        console.log("SimpleTempleHook:", hookAddress);
        console.log("PoolManager:", address(POOLMANAGER));
        console.log("PositionManager:", address(posm));

        // Setup currencies - Temple as currency0 for one-sided bonding curve
        Currency currency0 = Currency.wrap(templeToken); // Temple
        Currency currency1 = Currency.wrap(usdcToken); // USDC or Mock USDC

        // Create pool key
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
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

        // Position 1: 40% of supply, $0.0001 -> $0.000223 (early adopters, whale-resistant)
        console.log("\n=== Position 1: 40% (4B tokens) - Early Adopters ===");
        uint256 amount1 = (totalTempleAmount * 4000) / 10000; // 4B tokens (40%)
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-92200),
            TickMath.getSqrtPriceAtTick(-84200),
            amount1,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[0] = abi.encode(poolKey, -92200, -84200, liquidity1, amount1, 0, msg.sender, abi.encode(""));
        console.log("Price: $0.0001 -> $0.000223 | Market Cap: $1M -> $2.2M");

        // Position 2: 20% of supply, $0.000223 -> $0.000497 (early growth)
        console.log("=== Position 2: 20% (2B tokens) - Early Growth ===");
        uint256 amount2 = (totalTempleAmount * 2000) / 10000; // 2B tokens (20%)
        uint128 liquidity2 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-84200),
            TickMath.getSqrtPriceAtTick(-76200),
            amount2,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[1] = abi.encode(poolKey, -84200, -76200, liquidity2, amount2, 0, msg.sender, abi.encode(""));
        console.log("Price: $0.000223 -> $0.000497 | Market Cap: $2.2M -> $5M");

        // Position 3: 12% of supply, $0.000497 -> $0.001107 (FOMO begins)
        console.log("=== Position 3: 12% (1.2B tokens) - FOMO Phase ===");
        uint256 amount3 = (totalTempleAmount * 1200) / 10000; // 1.2B tokens (12%)
        uint128 liquidity3 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-76200),
            TickMath.getSqrtPriceAtTick(-68200),
            amount3,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[2] = abi.encode(poolKey, -76200, -68200, liquidity3, amount3, 0, msg.sender, abi.encode(""));
        console.log("Price: $0.000497 -> $0.001107 | Market Cap: $5M -> $11M");

        // Position 4: 8% of supply, $0.001107 -> $0.002467 (scarcity hits)
        console.log("=== Position 4: 8% (0.8B tokens) - Scarcity ===");
        uint256 amount4 = (totalTempleAmount * 800) / 10000; // 0.8B tokens (8%)
        uint128 liquidity4 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-68200),
            TickMath.getSqrtPriceAtTick(-60200),
            amount4,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[3] = abi.encode(poolKey, -68200, -60200, liquidity4, amount4, 0, msg.sender, abi.encode(""));
        console.log("Price: $0.001107 -> $0.002467 | Market Cap: $11M -> $25M");

        // Position 5: 20% of supply, $0.002467 -> $1.00 (THE INFINITY POOL!)
        console.log("=== Position 5: 20% (2B tokens) - INFINITY POOL ===");
        uint256 amount5 = (totalTempleAmount * 2000) / 10000; // 2B tokens (20%)
        uint128 liquidity5 = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(-60200),
            TickMath.getSqrtPriceAtTick(0),
            amount5,  // Temple is currency0
            0         // USDC is currency1
        );
        actions = abi.encodePacked(actions, uint8(Actions.MINT_POSITION));
        params[4] = abi.encode(poolKey, -60200, 0, liquidity5, amount5, 0, msg.sender, abi.encode(""));
        console.log("Price: $0.002467 -> $1.00 (405x!) | Market Cap: $25M -> $10B");

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
        console.log("Liquidity: 100% of supply (10B Temple tokens, ZERO USDC)");
        console.log("Distribution: Exponential Decay (40/20/12/8/20)");
        console.log("Positions: 5 concentrated ranges");
        console.log("\n=== FUNDRAISING TARGETS ===");
        console.log("Positions 1-4 (80% sold): ~$3.8M raised for charity");
        console.log("Position 5 (infinity pool): Reaches $1/token if fully bought");
        console.log("\n=== READY FOR PRICE DISCOVERY ===");
        console.log("Users buy Temple with USDC, 5% of every swap goes to charity!");
        console.log("Price appreciation: 10,000x ($0.0001 -> $1.00)");
    }
}
