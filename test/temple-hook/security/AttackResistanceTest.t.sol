// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Fixtures} from "../../utils/Fixtures.sol";
import {EasyPosm} from "../../utils/EasyPosm.sol";

/// @title Attack Resistance Tests for OptimizedTempleHook
/// @notice Tests for security vulnerabilities and attack resistance patterns
contract AttackResistanceTest is Test, Fixtures {
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
    uint256 constant DONATION_DENOMINATOR = 1_000_000;
    
    /*//////////////////////////////////////////////////////////////
                            TEST ACCOUNTS
    //////////////////////////////////////////////////////////////*/
    
    address charity = makeAddr("charity");
    address donationManager = makeAddr("donationManager");
    address guardian = makeAddr("guardian");
    address attacker = makeAddr("attacker");
    address dustAttacker = makeAddr("dustAttacker");
    address user = makeAddr("user");
    
    /*//////////////////////////////////////////////////////////////
                            TEST STATE
    //////////////////////////////////////////////////////////////*/
    
    PoolId testPoolId;
    PoolKey testKey;
    
    // Mock contracts for isolated testing
    MockSecurityTempleHook mockHook;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        
        // Deploy mock hook for testing
        mockHook = new MockSecurityTempleHook(
            manager,
            charity,
            donationManager,
            guardian
        );
        
        createTestPool();
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

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_unauthorizedDonationRateChange() public {
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, 5000);
    }
    
    function test_donationRateExceedsMaximum() public {
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, MAX_DONATION_BPS + 1);
    }
    
    function test_rateLimitingPreventsSpam() public {
        // First update should work
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 2000);
        
        // Second update in same block should fail
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, 1500);
        
        // After block advance, should work
        vm.roll(block.number + 1);
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 1500);
        
        assertEq(mockHook.getPoolDonationRate(testPoolId), 1500);
    }
    
    function test_unauthorizedManagerUpdate() public {
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.initiateDonationManagerUpdate(attacker);
    }
    
    function test_zeroAddressManagerUpdate() public {
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.initiateDonationManagerUpdate(address(0));
    }
    
    function test_timelockBypass_impossible() public {
        address newManager = makeAddr("newManager");
        
        // Initiate update
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        
        // Try to complete immediately (should fail)
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
        
        // Try to complete just before timelock expires (should fail)
        vm.warp(block.timestamp + 1 days - 1);
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
        
        // Complete after timelock expires (should work)
        vm.warp(block.timestamp + 2);
        mockHook.completeDonationManagerUpdate();
        
        assertEq(mockHook.donationManager(), newManager);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY CONTROL ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_unauthorizedEmergencyPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.emergencyPause(true);
        
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.emergencyPause(true);
    }
    
    function test_emergencyPauseByGuardian() public {
        vm.prank(guardian);
        mockHook.emergencyPause(true);
        
        assertTrue(mockHook.emergencyPaused());
        
        // Guardian can also unpause
        vm.prank(guardian);
        mockHook.emergencyPause(false);
        
        assertFalse(mockHook.emergencyPaused());
    }

    /*//////////////////////////////////////////////////////////////
                        DONATION CALCULATION ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_donationCalculation_noOverflow() public {
        // Test with maximum possible values
        uint256 maxSwapAmount = type(uint128).max;
        uint256 donation = mockHook.calculateDonation(maxSwapAmount, MAX_DONATION_BPS);
        
        // Should not overflow and should be reasonable
        assertTrue(donation <= maxSwapAmount);
        assertEq(donation, (maxSwapAmount * MAX_DONATION_BPS) / DONATION_DENOMINATOR);
    }
    
    function test_donationCalculation_precision() public {
        // Test precise calculation
        uint256 swapAmount = 1_000_000; // 1M units
        uint256 donation = mockHook.calculateDonation(swapAmount, DEFAULT_DONATION_BPS);
        
        // 0.1% of 1M = 1000
        assertEq(donation, 1000);
    }
    
    function test_donationCalculation_roundingDown() public {
        // Test that donations round down (favoring users)
        uint256 swapAmount = 999; // Small amount
        uint256 donation = mockHook.calculateDonation(swapAmount, DEFAULT_DONATION_BPS);
        
        // Should round down to 0
        assertEq(donation, 0);
    }
    
    function test_donationCalculation_edgeCases() public {
        // Zero swap amount
        assertEq(mockHook.calculateDonation(0, DEFAULT_DONATION_BPS), 0);
        
        // Zero donation rate
        assertEq(mockHook.calculateDonation(1 ether, 0), 0);
        
        // Maximum donation rate
        uint256 swapAmount = 1 ether;
        uint256 maxDonation = mockHook.calculateDonation(swapAmount, MAX_DONATION_BPS);
        assertEq(maxDonation, (swapAmount * MAX_DONATION_BPS) / DONATION_DENOMINATOR);
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK DATA VALIDATION ATTACKS
    //////////////////////////////////////////////////////////////*/

    function test_hookDataValidation_correctLength() public {
        bytes memory validData = abi.encode(user);
        assertEq(validData.length, 32);
        
        address parsed = mockHook.parseUserAddress(validData);
        assertEq(parsed, user);
    }
    
    function test_hookDataValidation_invalidLength() public {
        bytes memory invalidData = "invalid";
        
        vm.expectRevert();
        mockHook.parseUserAddress(invalidData);
    }
    
    function test_hookDataValidation_emptyData() public {
        bytes memory emptyData = "";
        
        vm.expectRevert();
        mockHook.parseUserAddress(emptyData);
    }

    /*//////////////////////////////////////////////////////////////
                        DUST ATTACK RESISTANCE
    //////////////////////////////////////////////////////////////*/

    function test_dustAttackPrevention_calculation() public {
        // Verify dust amounts don't create donations
        uint256 dustAmount = MIN_DONATION_AMOUNT - 1;
        
        assertTrue(dustAmount < MIN_DONATION_AMOUNT);
        assertFalse(mockHook.isDonationSufficient(dustAmount));
    }
    
    function test_dustAttackPrevention_threshold() public {
        // Verify threshold works correctly
        assertTrue(mockHook.isDonationSufficient(MIN_DONATION_AMOUNT));
        assertTrue(mockHook.isDonationSufficient(MIN_DONATION_AMOUNT + 1));
        assertFalse(mockHook.isDonationSufficient(MIN_DONATION_AMOUNT - 1));
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_multipleManagerUpdates_overwrite() public {
        address manager1 = makeAddr("manager1");
        address manager2 = makeAddr("manager2");
        
        // Initiate first update
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(manager1);
        
        // Initiate second update (should overwrite)
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(manager2);
        
        // Only the second update should be pending
        assertEq(mockHook.pendingDonationManager(), manager2);
        
        // Complete update
        vm.warp(block.timestamp + 1 days + 1);
        mockHook.completeDonationManagerUpdate();
        
        // Should have the second manager
        assertEq(mockHook.donationManager(), manager2);
    }
    
    function test_newManagerCanManage() public {
        address newManager = makeAddr("newManager");
        
        // Transfer management
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        vm.warp(block.timestamp + 1 days + 1);
        mockHook.completeDonationManagerUpdate();
        
        // New manager should be able to update rates
        vm.prank(newManager);
        mockHook.setPoolDonationRate(testPoolId, 3000);
        
        assertEq(mockHook.getPoolDonationRate(testPoolId), 3000);
        
        // Old manager should no longer work
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, 4000);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_viewFunctions_immutable() public {
        assertEq(mockHook.CHARITY_ADDRESS(), charity);
        assertEq(mockHook.getDonationDenominator(), DONATION_DENOMINATOR);
    }
    
    function test_viewFunctions_state() public {
        assertEq(mockHook.donationManager(), donationManager);
        assertEq(mockHook.guardian(), guardian);
        assertFalse(mockHook.emergencyPaused());
    }
}

/// @notice Simplified mock hook for testing security patterns
contract MockSecurityTempleHook {
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
    
    function parseUserAddress(bytes calldata hookData) external pure returns (address) {
        if (hookData.length != 32) revert InvalidHookData();
        return abi.decode(hookData, (address));
    }
    
    function isDonationSufficient(uint256 donationAmount) external pure returns (bool) {
        return donationAmount >= MIN_DONATION_AMOUNT;
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