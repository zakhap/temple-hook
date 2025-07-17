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

/// @title Governance Tests for OptimizedTempleHook
/// @notice Tests for governance mechanisms, access control, and admin functions
contract GovernanceTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint160 constant HOOK_SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 constant DEFAULT_DONATION_BPS = 1000; // 0.1%
    uint256 constant MAX_DONATION_BPS = 10000; // 1%
    uint256 constant GOVERNANCE_DELAY = 1 days;
    
    /*//////////////////////////////////////////////////////////////
                            TEST ACCOUNTS
    //////////////////////////////////////////////////////////////*/
    
    address charity = makeAddr("charity");
    address donationManager = makeAddr("donationManager");
    address guardian = makeAddr("guardian");
    address newManager = makeAddr("newManager");
    address attacker = makeAddr("attacker");
    address user = makeAddr("user");
    
    /*//////////////////////////////////////////////////////////////
                            TEST STATE
    //////////////////////////////////////////////////////////////*/
    
    PoolId testPoolId;
    PoolKey testKey;
    
    // Mock hook for testing governance functions
    MockOptimizedTempleHook mockHook;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event DonationConfigUpdated(PoolId indexed poolId, uint256 newDonationBps);
    event DonationManagerUpdateInitiated(address newManager, uint256 effectiveTime);
    event DonationManagerUpdated(address oldManager, address newManager);
    event EmergencyPaused(bool paused);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        
        // Deploy mock hook for testing
        mockHook = new MockOptimizedTempleHook(
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
            hooks: IHooks(address(0)) // No actual hook needed for governance tests
        });
        
        testPoolId = testKey.toId();
        manager.initialize(testKey, HOOK_SQRT_PRICE_1_1);
    }

    /*//////////////////////////////////////////////////////////////
                        DONATION RATE CONFIG TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setPoolDonationRate_success() public {
        uint256 newRate = 2000; // 0.2%
        
        vm.expectEmit(true, false, false, true);
        emit DonationConfigUpdated(testPoolId, newRate);
        
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, newRate);
        
        assertEq(mockHook.getPoolDonationRate(testPoolId), newRate);
    }
    
    function test_setPoolDonationRate_onlyDonationManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, 2000);
    }
    
    function test_setPoolDonationRate_exceedsMaximum() public {
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, MAX_DONATION_BPS + 1);
    }
    
    function test_setPoolDonationRate_rateLimited() public {
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
    
    function test_setPoolDonationRate_zeroRate() public {
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 0);
        
        assertEq(mockHook.getPoolDonationRate(testPoolId), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DONATION MANAGER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initiateDonationManagerUpdate_success() public {
        vm.expectEmit(true, false, false, true);
        emit DonationManagerUpdateInitiated(newManager, block.timestamp + GOVERNANCE_DELAY);
        
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        
        assertEq(mockHook.pendingDonationManager(), newManager);
        assertEq(mockHook.governanceUpdateTime(), block.timestamp + GOVERNANCE_DELAY);
    }
    
    function test_initiateDonationManagerUpdate_onlyDonationManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.initiateDonationManagerUpdate(newManager);
    }
    
    function test_initiateDonationManagerUpdate_zeroAddress() public {
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.initiateDonationManagerUpdate(address(0));
    }
    
    function test_completeDonationManagerUpdate_success() public {
        // Initiate update
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        
        // Advance time past delay
        vm.warp(block.timestamp + GOVERNANCE_DELAY + 1);
        
        vm.expectEmit(true, false, false, true);
        emit DonationManagerUpdated(donationManager, newManager);
        
        mockHook.completeDonationManagerUpdate();
        
        assertEq(mockHook.donationManager(), newManager);
        assertEq(mockHook.pendingDonationManager(), address(0));
        assertEq(mockHook.governanceUpdateTime(), 0);
    }
    
    function test_completeDonationManagerUpdate_beforeDelay() public {
        // Initiate update
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        
        // Try to complete before delay
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
        
        // Try again just before delay ends
        vm.warp(block.timestamp + GOVERNANCE_DELAY - 1);
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
    }
    
    function test_completeDonationManagerUpdate_noPendingUpdate() public {
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyPause_guardianOnly() public {
        vm.expectEmit(true, false, false, true);
        emit EmergencyPaused(true);
        
        vm.prank(guardian);
        mockHook.emergencyPause(true);
        
        assertTrue(mockHook.emergencyPaused());
    }
    
    function test_emergencyPause_onlyGuardian() public {
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.emergencyPause(true);
        
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.emergencyPause(true);
    }
    
    function test_emergencyUnpause() public {
        // Pause first
        vm.prank(guardian);
        mockHook.emergencyPause(true);
        assertTrue(mockHook.emergencyPaused());
        
        // Then unpause
        vm.expectEmit(true, false, false, true);
        emit EmergencyPaused(false);
        
        vm.prank(guardian);
        mockHook.emergencyPause(false);
        
        assertFalse(mockHook.emergencyPaused());
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_newManagerCanManage() public {
        // Transfer management
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        vm.warp(block.timestamp + GOVERNANCE_DELAY + 1);
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
    
    function test_multiplePoolConfigs() public {
        // Create second pool
        PoolKey memory secondKey = PoolKey({
            currency0: currency1,
            currency1: currency0,
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });
        PoolId secondPoolId = secondKey.toId();
        
        // Set different rates
        vm.startPrank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 1000);
        vm.roll(block.number + 1);
        mockHook.setPoolDonationRate(secondPoolId, 2000);
        vm.stopPrank();
        
        // Verify independent configs
        assertEq(mockHook.getPoolDonationRate(testPoolId), 1000);
        assertEq(mockHook.getPoolDonationRate(secondPoolId), 2000);
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cannotBypassTimelock() public {
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(attacker);
        
        // Attacker cannot complete update early
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
        
        // Even if they manipulate time slightly
        vm.warp(block.timestamp + GOVERNANCE_DELAY - 1 seconds);
        vm.prank(attacker);
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
    }
    
    function test_cannotInitiateMultipleUpdates() public {
        // First update
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        
        // Second update should overwrite (not stack)
        address anotherManager = makeAddr("anotherManager");
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(anotherManager);
        
        // Only the latest update should be pending
        assertEq(mockHook.pendingDonationManager(), anotherManager);
        
        // Complete should use latest
        vm.warp(block.timestamp + GOVERNANCE_DELAY + 1);
        mockHook.completeDonationManagerUpdate();
        
        assertEq(mockHook.donationManager(), anotherManager);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_viewFunctions() public {
        assertEq(mockHook.CHARITY_ADDRESS(), charity);
        assertEq(mockHook.donationManager(), donationManager);
        assertEq(mockHook.guardian(), guardian);
        assertEq(mockHook.getDonationDenominator(), 1_000_000);
        assertFalse(mockHook.emergencyPaused());
    }
}

/// @notice Mock hook contract for testing governance functions
contract MockOptimizedTempleHook {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    struct DonationConfig {
        uint128 donationBps;
        uint128 lastUpdateBlock;
    }
    
    mapping(PoolId => DonationConfig) public poolConfigs;
    
    address public immutable CHARITY_ADDRESS;
    address public donationManager;
    address public pendingDonationManager;
    address public guardian;
    uint256 public governanceUpdateTime;
    bool public emergencyPaused;
    
    uint256 public constant GOVERNANCE_DELAY = 1 days;
    uint256 private constant DONATION_DENOMINATOR = 1_000_000;
    uint256 private constant MAX_DONATION_BPS = 10_000;

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
        IPoolManager,
        address _charity,
        address _donationManager,
        address _guardian
    ) {
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
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getPoolDonationRate(PoolId poolId) external view returns (uint256) {
        return poolConfigs[poolId].donationBps;
    }
    
    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }
}