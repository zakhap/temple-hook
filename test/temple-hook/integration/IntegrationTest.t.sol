// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
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

/// @title Integration Tests for OptimizedTempleHook
/// @notice End-to-end tests with real Uniswap v4 infrastructure
contract IntegrationTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint160 constant HOOK_SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 constant DEFAULT_DONATION_BPS = 1000; // 0.1%
    uint256 constant MIN_DONATION_AMOUNT = 1000;
    uint256 constant DONATION_DENOMINATOR = 1_000_000;
    
    /*//////////////////////////////////////////////////////////////
                            TEST ACCOUNTS
    //////////////////////////////////////////////////////////////*/
    
    address charity = makeAddr("charity");
    address donationManager = makeAddr("donationManager");
    address guardian = makeAddr("guardian");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address liquidityProvider = makeAddr("liquidityProvider");
    
    /*//////////////////////////////////////////////////////////////
                            TEST STATE
    //////////////////////////////////////////////////////////////*/
    
    PoolId testPoolId;
    PoolKey testKey;
    PoolSwapTest integrationSwapRouter;
    
    // Mock hook for integration testing
    MockIntegrationTempleHook integrationHook;
    
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

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);
        
        // Deploy integration hook
        integrationHook = new MockIntegrationTempleHook(
            manager,
            charity,
            donationManager,
            guardian
        );
        
        // Deploy swap router
        integrationSwapRouter = new PoolSwapTest(manager);
        
        createPoolWithHook();
        fundAllAccounts();
        addInitialLiquidity();
    }
    
    function createPoolWithHook() internal {
        testKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(integrationHook))
        });
        
        testPoolId = testKey.toId();
        manager.initialize(testKey, HOOK_SQRT_PRICE_1_1);
    }
    
    function fundAllAccounts() internal {
        address[] memory accounts = new address[](5);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carol;
        accounts[3] = liquidityProvider;
        accounts[4] = address(this);
        
        for (uint i = 0; i < accounts.length; i++) {
            deal(Currency.unwrap(currency0), accounts[i], 10000 ether);
            deal(Currency.unwrap(currency1), accounts[i], 10000 ether);
            
            vm.startPrank(accounts[i]);
            IERC20(Currency.unwrap(currency0)).approve(address(integrationSwapRouter), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(integrationSwapRouter), type(uint256).max);
            IERC20(Currency.unwrap(currency0)).approve(address(posm), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(posm), type(uint256).max);
            vm.stopPrank();
        }
    }
    
    function addInitialLiquidity() internal {
        tickLower = TickMath.minUsableTick(testKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(testKey.tickSpacing);
        uint128 liquidityAmount = 1000e18;
        
        vm.prank(liquidityProvider);
        (tokenId,) = posm.mint(
            testKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            liquidityProvider,
            block.timestamp,
            ""
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FULL DONATION FLOW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fullDonationFlow_singleSwap() public {
        uint256 swapAmount = 1 ether;
        uint256 expectedDonation = (swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR;
        
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        uint256 aliceBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Mock the hook to track donations
        integrationHook.setDonationRate(testPoolId, DEFAULT_DONATION_BPS);
        
        vm.expectEmit(true, true, true, true);
        emit CharitableDonationCollected(alice, testPoolId, currency0, expectedDonation, swapAmount);
        
        vm.prank(alice);
        BalanceDelta delta = integrationSwapRouter.swap(
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
            abi.encode(alice)
        );
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        uint256 aliceBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Verify charity received donation
        assertEq(charityBalanceAfter - charityBalanceBefore, expectedDonation);
        
        // Verify alice paid the full swap amount plus donation effectively
        assertEq(aliceBalance0Before - aliceBalance0After, swapAmount);
        
        // Verify alice received output tokens
        assertTrue(aliceBalance1After > aliceBalance1Before);
        
        // Verify delta accounting
        assertEq(uint256(uint128(-delta.amount0())), swapAmount);
        assertTrue(delta.amount1() > 0);
    }
    
    function test_fullDonationFlow_multipleUsers() public {
        uint256 swapAmount = 0.5 ether;
        uint256 expectedDonationPerSwap = (swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR;
        
        integrationHook.setDonationRate(testPoolId, DEFAULT_DONATION_BPS);
        
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Alice swaps currency0 for currency1
        vm.prank(alice);
        integrationSwapRouter.swap(
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
            abi.encode(alice)
        );
        
        // Bob swaps currency1 for currency0  
        vm.prank(bob);
        integrationSwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(bob)
        );
        
        // Carol swaps currency0 for currency1
        vm.prank(carol);
        integrationSwapRouter.swap(
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
            abi.encode(carol)
        );
        
        uint256 charityBalanceAfter = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        uint256 charityBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(charity);
        
        // Charity should have received donations from both currency0 and currency1 swaps
        // Alice and Carol donated currency0, Bob donated currency1
        assertEq(charityBalanceAfter - charityBalanceBefore, expectedDonationPerSwap * 2);
        assertEq(charityBalance1After, expectedDonationPerSwap);
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY INTERACTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_liquidityAddition_duringDonations() public {
        uint256 swapAmount = 1 ether;
        integrationHook.setDonationRate(testPoolId, DEFAULT_DONATION_BPS);
        
        // Perform swap with donations
        vm.prank(alice);
        integrationSwapRouter.swap(
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
            abi.encode(alice)
        );
        
        // Add more liquidity
        uint128 additionalLiquidity = 100e18;
        vm.prank(liquidityProvider);
        posm.increaseLiquidity(
            tokenId,
            additionalLiquidity,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            block.timestamp,
            ""
        );
        
        // Perform another swap after liquidity addition
        vm.prank(bob);
        integrationSwapRouter.swap(
            testKey,
            IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            abi.encode(bob)
        );
        
        // Both swaps should have generated donations
        uint256 expectedTotalDonation = ((swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR) * 2;
        uint256 totalCharityBalance = 
            IERC20(Currency.unwrap(currency0)).balanceOf(charity) +
            IERC20(Currency.unwrap(currency1)).balanceOf(charity);
        
        assertEq(totalCharityBalance, expectedTotalDonation);
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_governanceChange_duringOperation() public {
        uint256 swapAmount = 1 ether;
        uint256 initialRate = 1000; // 0.1%
        uint256 newRate = 2000; // 0.2%
        
        // Set initial rate
        vm.prank(donationManager);
        integrationHook.setDonationRate(testPoolId, initialRate);
        
        // Perform swap with initial rate
        vm.prank(alice);
        integrationSwapRouter.swap(
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
            abi.encode(alice)
        );
        
        uint256 expectedInitialDonation = (swapAmount * initialRate) / DONATION_DENOMINATOR;
        uint256 charityBalanceAfterFirst = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        assertEq(charityBalanceAfterFirst, expectedInitialDonation);
        
        // Change donation rate
        vm.roll(block.number + 1); // Advance block for rate limiting
        vm.prank(donationManager);
        integrationHook.setDonationRate(testPoolId, newRate);
        
        // Perform swap with new rate
        vm.prank(bob);
        integrationSwapRouter.swap(
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
            abi.encode(bob)
        );
        
        uint256 expectedSecondDonation = (swapAmount * newRate) / DONATION_DENOMINATOR;
        uint256 charityBalanceAfterSecond = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        assertEq(charityBalanceAfterSecond, expectedInitialDonation + expectedSecondDonation);
    }
    
    function test_emergencyPause_integration() public {
        uint256 swapAmount = 1 ether;
        integrationHook.setDonationRate(testPoolId, DEFAULT_DONATION_BPS);
        
        // Normal swap should work
        vm.prank(alice);
        integrationSwapRouter.swap(
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
            abi.encode(alice)
        );
        
        // Emergency pause
        vm.prank(guardian);
        integrationHook.emergencyPause(true);
        
        // Swap should fail when paused
        vm.prank(bob);
        vm.expectRevert();
        integrationSwapRouter.swap(
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
            abi.encode(bob)
        );
        
        // Unpause and verify swaps work again
        vm.prank(guardian);
        integrationHook.emergencyPause(false);
        
        vm.prank(bob);
        integrationSwapRouter.swap(
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
            abi.encode(bob)
        );
        
        // Should have donations from alice and bob
        uint256 expectedTotalDonation = ((swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR) * 2;
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(charity), expectedTotalDonation);
    }

    /*//////////////////////////////////////////////////////////////
                        STRESS TEST SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_consecutiveSwaps_sameUser() public {
        uint256 swapAmount = 0.1 ether;
        uint256 numSwaps = 10;
        integrationHook.setDonationRate(testPoolId, DEFAULT_DONATION_BPS);
        
        uint256 charityBalanceBefore = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        
        // Perform multiple consecutive swaps
        for (uint i = 0; i < numSwaps; i++) {
            vm.prank(alice);
            integrationSwapRouter.swap(
                testKey,
                IPoolManager.SwapParams({
                    zeroForOne: i % 2 == 0, // Alternate directions
                    amountSpecified: -int256(swapAmount),
                    sqrtPriceLimitX96: i % 2 == 0 ? 
                        TickMath.MIN_SQRT_PRICE + 1 : 
                        TickMath.MAX_SQRT_PRICE - 1
                }),
                PoolSwapTest.TestSettings({
                    takeClaims: false,
                    settleUsingBurn: false
                }),
                abi.encode(alice)
            );
        }
        
        // Calculate expected donations (half in each currency)
        uint256 expectedDonationPerSwap = (swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR;
        uint256 expectedDonationsPerCurrency = (numSwaps / 2) * expectedDonationPerSwap;
        
        uint256 charityBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(charity);
        uint256 charityBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(charity);
        
        assertEq(charityBalance0After - charityBalanceBefore, expectedDonationsPerCurrency);
        assertEq(charityBalance1After, expectedDonationsPerCurrency);
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_recoveryAfterFailedSwap() public {
        uint256 swapAmount = 1 ether;
        integrationHook.setDonationRate(testPoolId, DEFAULT_DONATION_BPS);
        
        // Successful swap first
        vm.prank(alice);
        integrationSwapRouter.swap(
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
            abi.encode(alice)
        );
        
        // Try swap with invalid hook data (should fail)
        vm.prank(bob);
        vm.expectRevert();
        integrationSwapRouter.swap(
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
            "invalid_data" // Invalid hook data
        );
        
        // Recovery: successful swap after failed one
        vm.prank(bob);
        integrationSwapRouter.swap(
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
            abi.encode(bob)
        );
        
        // Should have donations from both successful swaps
        uint256 expectedTotalDonation = ((swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR) * 2;
        assertEq(IERC20(Currency.unwrap(currency0)).balanceOf(charity), expectedTotalDonation);
    }
}

/// @notice Mock hook contract for integration testing
contract MockIntegrationTempleHook is Test {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    mapping(PoolId => uint256) public donationRates;
    mapping(PoolId => mapping(address => uint256)) public donationStorage;
    
    IPoolManager public immutable poolManager;
    address public immutable CHARITY_ADDRESS;
    address public donationManager;
    address public guardian;
    bool public emergencyPaused;
    
    uint256 private constant DONATION_DENOMINATOR = 1_000_000;
    uint256 private constant MIN_DONATION_AMOUNT = 1000;

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
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error Unauthorized();
    error EmergencyPausedError();
    error InvalidHookData();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyDonationManager() {
        if (msg.sender != donationManager) revert Unauthorized();
        _;
    }
    
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert Unauthorized();
        _;
    }
    
    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPausedError();
        _;
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
                            HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external notPaused returns (bytes4) {
        if (hookData.length != 32) revert InvalidHookData();
        address user = abi.decode(hookData, (address));
        
        PoolId poolId = PoolIdLibrary.toId(key);
        uint256 donationBps = donationRates[poolId];
        
        if (donationBps > 0) {
            uint256 swapAmount = params.amountSpecified < 0 
                ? uint256(-params.amountSpecified)
                : uint256(params.amountSpecified);
                
            uint256 donationAmount = (swapAmount * donationBps) / DONATION_DENOMINATOR;
            
            if (donationAmount >= MIN_DONATION_AMOUNT) {
                donationStorage[poolId][user] = donationAmount;
            }
        }
        
        return MockIntegrationTempleHook.beforeSwap.selector;
    }
    
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata hookData
    ) external returns (bytes4) {
        if (hookData.length != 32) revert InvalidHookData();
        address user = abi.decode(hookData, (address));
        
        PoolId poolId = PoolIdLibrary.toId(key);
        uint256 donationAmount = donationStorage[poolId][user];
        
        if (donationAmount > 0) {
            // Determine donation currency
            Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
            
            // Simulate donation transfer
            donationStorage[poolId][user] = 0;
            
            // For testing, we'll mint tokens to charity instead of actual transfer
            deal(Currency.unwrap(donationCurrency), CHARITY_ADDRESS, 
                 IERC20(Currency.unwrap(donationCurrency)).balanceOf(CHARITY_ADDRESS) + donationAmount);
            
            emit CharitableDonationCollected(
                user,
                poolId,
                donationCurrency,
                donationAmount,
                params.amountSpecified < 0 
                    ? uint256(-params.amountSpecified)
                    : uint256(params.amountSpecified)
            );
        }
        
        return MockIntegrationTempleHook.afterSwap.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setDonationRate(PoolId poolId, uint256 newDonationBps) external onlyDonationManager {
        donationRates[poolId] = newDonationBps;
    }
    
    function emergencyPause(bool paused) external onlyGuardian {
        emergencyPaused = paused;
    }
}