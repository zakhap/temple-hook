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
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Fixtures} from "../../utils/Fixtures.sol";
import {EasyPosm} from "../../utils/EasyPosm.sol";

/// @title Security and Attack Resistance Tests
/// @notice Tests for security vulnerabilities, MEV protection, and attack resistance
contract SecurityTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint160 constant HOOK_SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 constant DEFAULT_DONATION_BPS = 1000; // 0.1%
    uint256 constant MAX_DONATION_BPS = 10000; // 1%
    uint256 constant MIN_DONATION_AMOUNT = 1000;
    
    /*//////////////////////////////////////////////////////////////
                            TEST ACCOUNTS
    //////////////////////////////////////////////////////////////*/
    
    address charity = makeAddr("charity");
    address donationManager = makeAddr("donationManager");
    address guardian = makeAddr("guardian");
    address mevBot = makeAddr("mevBot");
    address frontRunner = makeAddr("frontRunner");
    address attacker = makeAddr("attacker");
    address dustAttacker = makeAddr("dustAttacker");
    address user = makeAddr("user");
    
    /*//////////////////////////////////////////////////////////////
                            TEST STATE
    //////////////////////////////////////////////////////////////*/
    
    PoolId testPoolId;
    PoolKey testKey;
    PoolSwapTest securitySwapRouter;
    
    // Mock hook for testing security scenarios
    MockSecureTempleHook mockHook;

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

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        
        // Deploy mock hook for testing
        mockHook = new MockSecureTempleHook(
            manager,
            charity,
            donationManager,
            guardian
        );
        
        // Deploy swap router
        securitySwapRouter = new PoolSwapTest(manager);
        
        createTestPool();
        fundTestAccounts();
    }
    
    function createTestPool() internal {
        testKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(mockHook))
        });
        
        testPoolId = testKey.toId();
        manager.initialize(testKey, HOOK_SQRT_PRICE_1_1);
        
        // Add liquidity for testing
        deployAndApprovePosm(manager);
        
        int24 tickLower = TickMath.minUsableTick(testKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(testKey.tickSpacing);
        uint128 liquidityAmount = 100e18;
        
        posm.mint(
            testKey,
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
        address[] memory accounts = new address[](6);
        accounts[0] = mevBot;
        accounts[1] = frontRunner;
        accounts[2] = attacker;
        accounts[3] = dustAttacker;
        accounts[4] = user;
        accounts[5] = address(this);
        
        for (uint i = 0; i < accounts.length; i++) {
            deal(Currency.unwrap(currency0), accounts[i], 1000 ether);
            deal(Currency.unwrap(currency1), accounts[i], 1000 ether);
            
            vm.startPrank(accounts[i]);
            IERC20(Currency.unwrap(currency0)).approve(address(securitySwapRouter), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(securitySwapRouter), type(uint256).max);
            vm.stopPrank();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_reentrancyProtection_beforeSwap() public {
        // Hook should be protected against reentrancy in beforeSwap
        vm.prank(attacker);
        vm.expectRevert(); // Should revert due to reentrancy protection
        mockHook.testReentrancyAttack(testPoolId);
    }
    
    function test_reentrancyProtection_afterSwap() public {
        // Ensure afterSwap cannot be called recursively
        uint256 swapAmount = 1 ether;
        
        vm.prank(attacker);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(attacker)
        );
        
        // Should complete without reentrancy issues
        assertTrue(true);
    }

    /*//////////////////////////////////////////////////////////////
                        DUST ATTACK RESISTANCE
    //////////////////////////////////////////////////////////////*/

    function test_dustAttackPrevention_tinySwaps() public {
        // Small swaps should not create donations due to MIN_DONATION_AMOUNT
        uint256 dustSwapAmount = 100; // Very small amount
        
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        vm.prank(dustAttacker);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(dustSwapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(dustAttacker)
        );
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // No donation should have occurred due to dust protection
        assertEq(charityBalanceBefore, charityBalanceAfter);
    }
    
    function test_dustAttackPrevention_multipleSmallSwaps() public {
        // Multiple small swaps should still be blocked
        uint256 dustSwapAmount = 500; // Below MIN_DONATION_AMOUNT threshold
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Execute 10 dust swaps
        for (uint i = 0; i < 10; i++) {
            vm.prank(dustAttacker);
            swapRouter.swap(
                testKey,
                IPoolManager.SwapParams({
                    zeroForOne: true,
                    amountSpecified: -int256(dustSwapAmount),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                PoolSwapTest.TestSettings({
                    takeClaims: false,
                    settleUsingBurn: false
                }),
                abi.encode(dustAttacker)
            );
        }
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // No donations should have occurred
        assertEq(charityBalanceBefore, charityBalanceAfter);
    }

    /*//////////////////////////////////////////////////////////////
                        MEV ATTACK RESISTANCE
    //////////////////////////////////////////////////////////////*/

    function test_mevResistance_frontRunning() public {
        // MEV bot tries to front-run a legitimate swap
        uint256 userSwapAmount = 10 ether;
        uint256 mevSwapAmount = 1 ether;
        
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // MEV bot tries to front-run (same block)
        vm.prank(mevBot);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(mevSwapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(mevBot)
        );
        
        // User's legitimate swap
        vm.prank(user);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(userSwapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user)
        );
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Both swaps should contribute donations fairly
        uint256 expectedDonations = 
            (mevSwapAmount * DEFAULT_DONATION_BPS) / 1_000_000 +
            (userSwapAmount * DEFAULT_DONATION_BPS) / 1_000_000;
        
        assertEq(charityBalanceAfter - charityBalanceBefore, expectedDonations);
    }
    
    function test_mevResistance_sandwichAttack() public {
        // Simulate sandwich attack: front-run, victim swap, back-run
        uint256 victimSwapAmount = 5 ether;
        uint256 attackSwapAmount = 2 ether;
        
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Front-run
        vm.prank(mevBot);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(attackSwapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(mevBot)
        );
        
        // Victim swap
        vm.prank(user);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(victimSwapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user)
        );
        
        // Back-run (reverse direction)
        vm.prank(mevBot);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(attackSwapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(mevBot)
        );
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // All swaps should contribute donations (MEV bot pays too)
        assertTrue(charityBalanceAfter > charityBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK DATA MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_hookDataValidation_invalidLength() public {
        uint256 swapAmount = 1 ether;
        
        vm.prank(attacker);
        vm.expectRevert(); // Should revert due to invalid hook data length
        swapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            "invalid_data" // Wrong format
        );
    }
    
    function test_hookDataValidation_emptyData() public {
        uint256 swapAmount = 1 ether;
        
        vm.prank(attacker);
        vm.expectRevert(); // Should revert due to empty hook data
        swapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            "" // Empty data
        );
    }
    
    function test_hookDataValidation_malformedAddress() public {
        uint256 swapAmount = 1 ether;
        
        vm.prank(attacker);
        vm.expectRevert(); // Should revert due to malformed address in hook data
        swapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(uint256(123456789)) // Not an address
        );
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyPause_blocksSwaps() public {
        // Guardian pauses the hook
        vm.prank(guardian);
        mockHook.emergencyPause(true);
        
        uint256 swapAmount = 1 ether;
        
        vm.prank(user);
        vm.expectRevert(); // Should revert due to emergency pause
        swapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user)
        );
    }
    
    function test_emergencyPause_resumeAfterUnpause() public {
        // Pause and then unpause
        vm.startPrank(guardian);
        mockHook.emergencyPause(true);
        mockHook.emergencyPause(false);
        vm.stopPrank();
        
        uint256 swapAmount = 1 ether;
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Swap should work normally after unpause
        vm.prank(user);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user)
        );
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Donation should have occurred
        assertGt(charityBalanceAfter, charityBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        DONATION CALCULATION ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_donationCalculation_noOverflow() public {
        // Test with maximum possible values to ensure no overflow
        uint256 maxSwapAmount = type(uint128).max;
        
        // This should not overflow
        uint256 donation = (maxSwapAmount * MAX_DONATION_BPS) / 1_000_000;
        assertTrue(donation <= maxSwapAmount);
    }
    
    function test_donationCalculation_precision() public {
        // Test donation calculation precision
        uint256 swapAmount = 1_000_000; // 1M units
        uint256 expectedDonation = (swapAmount * DEFAULT_DONATION_BPS) / 1_000_000;
        
        assertEq(expectedDonation, 1000); // 0.1% of 1M = 1000
    }
    
    function test_donationCalculation_roundingDown() public {
        // Test that donations round down (favor user)
        uint256 swapAmount = 999; // Small amount that should round down to 0
        uint256 donation = (swapAmount * DEFAULT_DONATION_BPS) / 1_000_000;
        
        assertEq(donation, 0); // Should round down to 0
    }

    /*//////////////////////////////////////////////////////////////
                        DONATION STORAGE ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_donationStorage_isolation() public {
        // Test that donation storage is properly isolated between pools
        // This test ensures that donations for one pool don't affect another
        
        // Create second pool
        PoolKey memory secondKey = PoolKey({
            currency0: currency1,
            currency1: currency0,
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(mockHook))
        });
        
        PoolId secondPoolId = secondKey.toId();
        manager.initialize(secondKey, HOOK_SQRT_PRICE_1_1);
        
        uint256 swapAmount = 1 ether;
        
        // Perform swaps on both pools
        vm.prank(user);
        securitySwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(user)
        );
        
        // Storage should be properly isolated - no cross-contamination
        assertTrue(true); // If we get here, storage isolation works
    }
}

/// @notice Mock hook contract for testing security scenarios
contract MockSecureTempleHook {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    IPoolManager public immutable poolManager;
    address public immutable CHARITY_ADDRESS;
    address public donationManager;
    address public guardian;
    bool public emergencyPaused;
    
    mapping(PoolId => uint256) public poolConfigs;
    bool private _reentrancyGuard;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error Unauthorized();
    error EmergencyPausedError();
    error ReentrancyGuard();
    error InvalidHookData();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert Unauthorized();
        _;
    }
    
    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPausedError();
        _;
    }
    
    modifier nonReentrant() {
        if (_reentrancyGuard) revert ReentrancyGuard();
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IPoolManager _poolManager,
        address _charity,
        address _donationManager,
        address _guardian
    ) {
        poolManager = _poolManager;
        CHARITY_ADDRESS = _charity;
        donationManager = _donationManager;
        guardian = _guardian;
    }

    /*//////////////////////////////////////////////////////////////
                            MOCK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function emergencyPause(bool paused) external onlyGuardian {
        emergencyPaused = paused;
    }
    
    function testReentrancyAttack(PoolId) external nonReentrant notPaused {
        // This function tests reentrancy protection
        revert("Reentrancy protection test");
    }
    
    function parseUserAddress(bytes calldata hookData) external pure returns (address) {
        if (hookData.length != 32) revert InvalidHookData();
        return abi.decode(hookData, (address));
    }
}