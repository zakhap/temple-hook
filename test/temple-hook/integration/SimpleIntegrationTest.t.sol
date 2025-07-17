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

/// @title Simple Integration Tests for Temple Hook Components
/// @notice Tests integration between hook components without requiring actual hook deployment
contract SimpleIntegrationTest is Test, Fixtures {
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
    
    /*//////////////////////////////////////////////////////////////
                            TEST STATE
    //////////////////////////////////////////////////////////////*/
    
    PoolId testPoolId;
    PoolKey testKey;
    PoolSwapTest simpleSwapRouter;
    
    // Helper contract for testing integration patterns
    IntegrationHelper helper;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);
        
        // Deploy helper contract
        helper = new IntegrationHelper(
            manager,
            charity,
            donationManager,
            guardian
        );
        
        // Deploy swap router
        simpleSwapRouter = new PoolSwapTest(manager);
        
        createTestPool();
        fundTestAccounts();
        addLiquidity();
    }
    
    function createTestPool() internal {
        testKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)) // No hook for simplified testing
        });
        
        testPoolId = testKey.toId();
        manager.initialize(testKey, HOOK_SQRT_PRICE_1_1);
    }
    
    function fundTestAccounts() internal {
        address[] memory accounts = new address[](4);
        accounts[0] = alice;
        accounts[1] = bob;
        accounts[2] = carol;
        accounts[3] = address(this);
        
        for (uint i = 0; i < accounts.length; i++) {
            deal(Currency.unwrap(currency0), accounts[i], 1000 ether);
            deal(Currency.unwrap(currency1), accounts[i], 1000 ether);
            
            vm.startPrank(accounts[i]);
            IERC20(Currency.unwrap(currency0)).approve(address(simpleSwapRouter), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(simpleSwapRouter), type(uint256).max);
            vm.stopPrank();
        }
    }
    
    function addLiquidity() internal {
        int24 tickLower = TickMath.minUsableTick(testKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(testKey.tickSpacing);
        uint128 liquidityAmount = 1000e18;
        
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

    /*//////////////////////////////////////////////////////////////
                        DONATION CALCULATION INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_donationCalculation_integration() public {
        uint256 swapAmount = 1 ether;
        uint256 donationBps = 1000; // 0.1%
        
        // Test donation calculation
        uint256 donation = helper.calculateDonation(swapAmount, donationBps);
        uint256 expected = (swapAmount * donationBps) / DONATION_DENOMINATOR;
        
        assertEq(donation, expected);
        assertTrue(helper.isDonationSufficient(donation));
    }
    
    function test_donationCalculation_multipleRates() public {
        uint256 swapAmount = 10 ether;
        uint256[] memory rates = new uint256[](5);
        rates[0] = 500;   // 0.05%
        rates[1] = 1000;  // 0.1%
        rates[2] = 2500;  // 0.25%
        rates[3] = 5000;  // 0.5%
        rates[4] = 10000; // 1%
        
        for (uint i = 0; i < rates.length; i++) {
            uint256 donation = helper.calculateDonation(swapAmount, rates[i]);
            uint256 expected = (swapAmount * rates[i]) / DONATION_DENOMINATOR;
            
            assertEq(donation, expected);
            assertTrue(donation <= swapAmount); // Should never exceed swap amount
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE WORKFLOW INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_governanceWorkflow_complete() public {
        // Initial configuration
        vm.prank(donationManager);
        helper.setPoolDonationRate(testPoolId, 1000);
        assertEq(helper.getPoolDonationRate(testPoolId), 1000);
        
        // Update donation rate
        vm.roll(block.number + 1);
        vm.prank(donationManager);
        helper.setPoolDonationRate(testPoolId, 2000);
        assertEq(helper.getPoolDonationRate(testPoolId), 2000);
        
        // Initiate manager transfer
        address newManager = makeAddr("newManager");
        vm.prank(donationManager);
        helper.initiateDonationManagerUpdate(newManager);
        
        assertEq(helper.pendingDonationManager(), newManager);
        assertTrue(helper.governanceUpdateTime() > block.timestamp);
        
        // Complete manager transfer
        vm.warp(block.timestamp + 1 days + 1);
        helper.completeDonationManagerUpdate();
        
        assertEq(helper.donationManager(), newManager);
        assertEq(helper.pendingDonationManager(), address(0));
        
        // New manager can update rates
        vm.roll(block.number + 1);
        vm.prank(newManager);
        helper.setPoolDonationRate(testPoolId, 3000);
        assertEq(helper.getPoolDonationRate(testPoolId), 3000);
    }
    
    function test_emergencyControls_integration() public {
        // Normal state
        assertFalse(helper.emergencyPaused());
        
        // Guardian can pause
        vm.prank(guardian);
        helper.emergencyPause(true);
        assertTrue(helper.emergencyPaused());
        
        // Guardian can unpause
        vm.prank(guardian);
        helper.emergencyPause(false);
        assertFalse(helper.emergencyPaused());
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-POOL SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_multiPool_isolation() public {
        // Create additional pools
        PoolKey[] memory keys = new PoolKey[](3);
        PoolId[] memory ids = new PoolId[](3);
        
        for (uint i = 0; i < 3; i++) {
            keys[i] = PoolKey({
                currency0: i % 2 == 0 ? currency0 : currency1,
                currency1: i % 2 == 0 ? currency1 : currency0,
                fee: uint24(500 + i * 1000),
                tickSpacing: 60,
                hooks: IHooks(address(0))
            });
            ids[i] = keys[i].toId();
        }
        
        // Set different donation rates for each pool
        uint256[] memory rates = new uint256[](3);
        rates[0] = 500;
        rates[1] = 1500;
        rates[2] = 2500;
        
        for (uint i = 0; i < 3; i++) {
            vm.prank(donationManager);
            helper.setPoolDonationRate(ids[i], rates[i]);
            vm.roll(block.number + 1);
        }
        
        // Verify isolation
        for (uint i = 0; i < 3; i++) {
            assertEq(helper.getPoolDonationRate(ids[i]), rates[i]);
        }
        
        // Update one pool's rate
        vm.prank(donationManager);
        helper.setPoolDonationRate(ids[1], 7500);
        
        // Verify other pools unchanged
        assertEq(helper.getPoolDonationRate(ids[0]), rates[0]);
        assertEq(helper.getPoolDonationRate(ids[1]), 7500);
        assertEq(helper.getPoolDonationRate(ids[2]), rates[2]);
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE EFFICIENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_storageOptimization_packingUnpacking() public {
        // Test storage packing for donation info
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 0;
        amounts[1] = 1000;
        amounts[2] = type(uint96).max / 2;
        amounts[3] = type(uint96).max;
        amounts[4] = 123456789;
        
        address[] memory users = new address[](5);
        users[0] = address(0);
        users[1] = alice;
        users[2] = bob;
        users[3] = address(type(uint160).max);
        users[4] = makeAddr("testUser");
        
        for (uint i = 0; i < amounts.length; i++) {
            for (uint j = 0; j < users.length; j++) {
                if (amounts[i] < (1 << 96)) { // Only test valid amounts
                    bytes32 packed = helper.packDonationInfo(amounts[i], users[j]);
                    (uint256 unpackedAmount, address unpackedUser) = helper.unpackDonationInfo(packed);
                    
                    assertEq(unpackedAmount, amounts[i]);
                    assertEq(unpackedUser, users[j]);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR HANDLING INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_errorHandling_invalidInputs() public {
        // Invalid donation rate
        vm.prank(donationManager);
        vm.expectRevert();
        helper.setPoolDonationRate(testPoolId, 50000); // > 1%
        
        // Invalid manager address
        vm.prank(donationManager);
        vm.expectRevert();
        helper.initiateDonationManagerUpdate(address(0));
        
        // Unauthorized access
        vm.prank(alice);
        vm.expectRevert();
        helper.setPoolDonationRate(testPoolId, 1000);
        
        vm.prank(alice);
        vm.expectRevert();
        helper.emergencyPause(true);
    }
    
    function test_errorHandling_timingConstraints() public {
        // Rate limiting
        vm.prank(donationManager);
        helper.setPoolDonationRate(testPoolId, 1000);
        
        vm.prank(donationManager);
        vm.expectRevert();
        helper.setPoolDonationRate(testPoolId, 2000); // Same block
        
        // Governance delay
        address newManager = makeAddr("newManager");
        vm.prank(donationManager);
        helper.initiateDonationManagerUpdate(newManager);
        
        vm.expectRevert();
        helper.completeDonationManagerUpdate(); // Too early
    }

    /*//////////////////////////////////////////////////////////////
                        SWAP SIMULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_swapSimulation_withoutHook() public {
        uint256 swapAmount = 1 ether;
        
        uint256 aliceBalance0Before = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceBalance1Before = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Perform actual swap without hook
        vm.prank(alice);
        BalanceDelta delta = simpleSwapRouter.swap(
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
            ""
        );
        
        uint256 aliceBalance0After = IERC20(Currency.unwrap(currency0)).balanceOf(alice);
        uint256 aliceBalance1After = IERC20(Currency.unwrap(currency1)).balanceOf(alice);
        
        // Verify swap worked
        assertEq(aliceBalance0Before - aliceBalance0After, swapAmount);
        assertTrue(aliceBalance1After > aliceBalance1Before);
        assertEq(uint256(uint128(-delta.amount0())), swapAmount);
        
        // Simulate what donation would be
        uint256 simulatedDonation = helper.calculateDonation(swapAmount, DEFAULT_DONATION_BPS);
        assertTrue(simulatedDonation > 0);
        assertTrue(helper.isDonationSufficient(simulatedDonation));
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_viewFunctions_consistency() public {
        // Test all view functions return consistent data
        assertEq(helper.CHARITY_ADDRESS(), charity);
        assertEq(helper.donationManager(), donationManager);
        assertEq(helper.guardian(), guardian);
        assertEq(helper.getDonationDenominator(), DONATION_DENOMINATOR);
        assertFalse(helper.emergencyPaused());
        
        // Set some state and verify
        vm.prank(donationManager);
        helper.setPoolDonationRate(testPoolId, 2500);
        assertEq(helper.getPoolDonationRate(testPoolId), 2500);
        
        vm.prank(guardian);
        helper.emergencyPause(true);
        assertTrue(helper.emergencyPaused());
    }
}

/// @notice Helper contract for testing integration patterns
contract IntegrationHelper {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    struct DonationConfig {
        uint128 donationBps;
        uint128 lastUpdateBlock;
    }
    
    mapping(PoolId => DonationConfig) public poolConfigs;
    
    IPoolManager public immutable poolManager;
    address public immutable CHARITY_ADDRESS;
    address public donationManager;
    address public pendingDonationManager;
    address public guardian;
    uint256 public governanceUpdateTime;
    bool public emergencyPaused;
    
    uint256 public constant GOVERNANCE_DELAY = 1 days;
    uint256 private constant DONATION_DENOMINATOR = 1_000_000;
    uint256 private constant MAX_DONATION_BPS = 10_000;
    uint256 private constant MIN_DONATION_AMOUNT = 1000;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event DonationConfigUpdated(PoolId indexed poolId, uint256 newDonationBps);
    event DonationManagerUpdateInitiated(address newManager, uint256 effectiveTime);
    event DonationManagerUpdated(address oldManager, address newManager);
    event EmergencyPaused(bool paused);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error Unauthorized();
    error InvalidDonationRate();
    error InvalidAddress();
    error GovernanceDelay();
    error RateLimited();

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
                            GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function setPoolDonationRate(PoolId poolId, uint256 newDonationBps) external onlyDonationManager {
        if (newDonationBps > MAX_DONATION_BPS) revert InvalidDonationRate();
        
        DonationConfig storage config = poolConfigs[poolId];
        if (config.lastUpdateBlock >= block.number) revert RateLimited();
        
        config.donationBps = uint128(newDonationBps);
        config.lastUpdateBlock = uint128(block.number);
        
        emit DonationConfigUpdated(poolId, newDonationBps);
    }
    
    function initiateDonationManagerUpdate(address newManager) external onlyDonationManager {
        if (newManager == address(0)) revert InvalidAddress();
        
        pendingDonationManager = newManager;
        governanceUpdateTime = block.timestamp + GOVERNANCE_DELAY;
        
        emit DonationManagerUpdateInitiated(newManager, governanceUpdateTime);
    }
    
    function completeDonationManagerUpdate() external {
        if (block.timestamp < governanceUpdateTime) revert GovernanceDelay();
        if (pendingDonationManager == address(0)) revert InvalidAddress();
        
        address oldManager = donationManager;
        donationManager = pendingDonationManager;
        pendingDonationManager = address(0);
        governanceUpdateTime = 0;
        
        emit DonationManagerUpdated(oldManager, donationManager);
    }
    
    function emergencyPause(bool paused) external onlyGuardian {
        emergencyPaused = paused;
        emit EmergencyPaused(paused);
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function calculateDonation(uint256 swapAmount, uint256 donationBps) external pure returns (uint256) {
        return (swapAmount * donationBps) / DONATION_DENOMINATOR;
    }
    
    function isDonationSufficient(uint256 donationAmount) external pure returns (bool) {
        return donationAmount >= MIN_DONATION_AMOUNT;
    }
    
    function packDonationInfo(uint256 amount, address user) external pure returns (bytes32) {
        return bytes32((uint256(uint160(user)) << 96) | amount);
    }
    
    function unpackDonationInfo(bytes32 data) external pure returns (uint256 amount, address user) {
        amount = uint256(data) & ((1 << 96) - 1);
        user = address(uint160(uint256(data) >> 96));
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getPoolDonationRate(PoolId poolId) external view returns (uint256) {
        return poolConfigs[poolId].donationBps;
    }
    
    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }
}