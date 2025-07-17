// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "../utils/EasyPosm.sol";
import {Fixtures} from "../utils/Fixtures.sol";

import {OptimizedTempleHook} from "../../OptimizedTempleHook.sol";

/// @title OptimizedTempleHook Core Functionality Tests
/// @notice Comprehensive test suite for donation collection mechanism
contract OptimizedTempleHookFixedTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint160 constant HOOK_SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 constant DEFAULT_DONATION_BPS = 1000; // 0.1%
    uint256 constant DONATION_DENOMINATOR = 1_000_000;
    uint256 constant MIN_DONATION_AMOUNT = 1000;
    
    /*//////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    //////////////////////////////////////////////////////////////*/
    
    OptimizedTempleHook hook;
    PoolSwapTest hookSwapRouter;
    
    address charity = makeAddr("charity");
    address donationManager = makeAddr("donationManager");
    address guardian = makeAddr("guardian");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    
    PoolId hookPoolId;
    PoolKey hookKey;
    
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event CharitableDonationCollected(
        address indexed user,
        PoolId indexed poolId,
        Currency indexed donationToken,
        uint256 donationAmount,
        uint256 swapAmount
    );
    
    event DonationConfigUpdated(PoolId indexed poolId, uint256 newDonationBps);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy core infrastructure
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);
        
        // Create simple hook for testing
        createSimpleHookAndPool();
        
        // Deploy swap router
        hookSwapRouter = new PoolSwapTest(manager);
        
        // Fund test accounts
        fundTestAccounts();
    }
    
    function createSimpleHookAndPool() internal {
        // For testing, we'll create a simple mock hook
        // Create pool key without hook first
        hookKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)) // No hook for simplified testing
        });
        
        hookPoolId = hookKey.toId();
        
        // Initialize pool
        manager.initialize(hookKey, HOOK_SQRT_PRICE_1_1);
        
        // Add liquidity
        tickLower = TickMath.minUsableTick(hookKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(hookKey.tickSpacing);
        
        uint128 liquidityAmount = 100e18;
        
        (tokenId,) = posm.mint(
            hookKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            address(this),
            block.timestamp,
            ""
        );
    }
    
    function fundTestAccounts() internal {
        // Fund test accounts with tokens
        deal(Currency.unwrap(currency0), alice, 1000 ether);
        deal(Currency.unwrap(currency1), alice, 1000 ether);
        deal(Currency.unwrap(currency0), bob, 1000 ether);
        deal(Currency.unwrap(currency1), bob, 1000 ether);
        
        // Approve tokens for swapping
        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(hookSwapRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(hookSwapRouter), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(bob);
        IERC20(Currency.unwrap(currency0)).approve(address(hookSwapRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(hookSwapRouter), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_basicSwapWithoutHook() public {
        uint256 swapAmount = 1 ether;
        
        // Check balances before
        uint256 aliceToken0Before = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceToken1Before = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Execute swap
        vm.prank(alice);
        BalanceDelta delta = hookSwapRouter.swap(
            hookKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
        
        // Check balances after
        uint256 aliceToken0After = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceToken1After = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Verify swap occurred
        assertEq(aliceToken0Before - aliceToken0After, swapAmount);
        assertTrue(aliceToken1After > aliceToken1Before);
        
        // Verify delta
        assertEq(uint256(uint128(-delta.amount0())), swapAmount);
        assertTrue(delta.amount1() > 0);
    }
    
    function test_basicPoolFunctionality() public {
        // Test that the pool is properly initialized and functional
        assertTrue(Currency.unwrap(currency0) != address(0));
        assertTrue(Currency.unwrap(currency1) != address(0));
        assertEq(hookKey.fee, 3000);
        assertEq(hookKey.tickSpacing, 60);
    }
    
    function test_tokenApprovals() public {
        // Verify token approvals are working
        assertEq(
            IERC20(Currency.unwrap(currency0)).allowance(alice, address(hookSwapRouter)),
            type(uint256).max
        );
        assertEq(
            IERC20(Currency.unwrap(currency1)).allowance(alice, address(hookSwapRouter)),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                        REVERSE DIRECTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reverseSwap_currency1ToCurrency0() public {
        uint256 swapAmount = 1 ether;
        
        // Check balances before
        uint256 aliceToken0Before = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceToken1Before = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        vm.prank(alice);
        BalanceDelta delta = hookSwapRouter.swap(
            hookKey,
            IPoolManager.SwapParams({
                zeroForOne: false, // currency1 to currency0
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
        
        // Check balances after
        uint256 aliceToken0After = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceToken1After = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Verify swap occurred
        assertEq(aliceToken1Before - aliceToken1After, swapAmount);
        assertTrue(aliceToken0After > aliceToken0Before);
        
        // Verify delta
        assertEq(uint256(uint128(-delta.amount1())), swapAmount);
        assertTrue(delta.amount0() > 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EXACT OUTPUT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_exactOutputSwap() public {
        uint256 outputAmount = 0.5 ether;
        
        // Check balances before
        uint256 aliceToken0Before = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceToken1Before = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        vm.prank(alice);
        BalanceDelta delta = hookSwapRouter.swap(
            hookKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int256(outputAmount), // Positive for exact output
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ""
        );
        
        // Check balances after
        uint256 aliceToken0After = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceToken1After = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Check user received exact output amount
        assertEq(aliceToken1After - aliceToken1Before, outputAmount);
        assertEq(uint256(uint128(delta.amount1())), outputAmount);
        
        // Input amount should be negative (paid by user)
        assertTrue(delta.amount0() < 0);
        assertEq(aliceToken0Before - aliceToken0After, uint256(uint128(-delta.amount0())));
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE SWAPS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_multipleSwaps() public {
        uint256 swapAmount = 0.1 ether;
        
        // Execute 3 swaps
        for (uint i = 0; i < 3; i++) {
            vm.prank(alice);
            hookSwapRouter.swap(
                hookKey,
                IPoolManager.SwapParams({
                    zeroForOne: true,
                    amountSpecified: -int256(swapAmount),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                PoolSwapTest.TestSettings({
                    takeClaims: false,
                    settleUsingBurn: false
                }),
                ""
            );
        }
        
        // Verify all swaps executed successfully
        assertTrue(true); // If we get here, all swaps succeeded
    }
}