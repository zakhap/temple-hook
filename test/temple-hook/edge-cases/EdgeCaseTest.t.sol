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
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Fixtures} from "../../utils/Fixtures.sol";
import {EasyPosm} from "../../utils/EasyPosm.sol";

/// @title Edge Case and Boundary Condition Tests
/// @notice Tests for edge cases, boundary conditions, and extreme scenarios
contract EdgeCaseTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using SafeCast for int256;

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
    address user = makeAddr("user");
    
    /*//////////////////////////////////////////////////////////////
                            TEST STATE
    //////////////////////////////////////////////////////////////*/
    
    PoolId testPoolId;
    PoolKey testKey;
    
    // Mock contracts for testing edge cases
    MockEdgeCaseTempleHook mockHook;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        
        // Deploy mock hook for testing
        mockHook = new MockEdgeCaseTempleHook(
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
                        BOUNDARY VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_maximumSwapAmount() public {
        uint256 maxAmount = type(uint128).max;
        
        // Should handle maximum swap amount without overflow
        uint256 donation = mockHook.calculateDonation(maxAmount, DEFAULT_DONATION_BPS);
        
        assertTrue(donation > 0);
        assertTrue(donation <= maxAmount);
        assertEq(donation, (maxAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR);
    }
    
    function test_minimumSwapAmount() public {
        uint256 minAmount = 1;
        
        // Should handle minimum swap amount
        uint256 donation = mockHook.calculateDonation(minAmount, DEFAULT_DONATION_BPS);
        
        // Should round down to 0 for tiny amounts
        assertEq(donation, 0);
    }
    
    function test_donationThresholdBoundary() public {
        // Test amounts around the minimum donation threshold
        uint256 belowThreshold = MIN_DONATION_AMOUNT - 1;
        uint256 atThreshold = MIN_DONATION_AMOUNT;
        uint256 aboveThreshold = MIN_DONATION_AMOUNT + 1;
        
        assertFalse(mockHook.isDonationSufficient(belowThreshold));
        assertTrue(mockHook.isDonationSufficient(atThreshold));
        assertTrue(mockHook.isDonationSufficient(aboveThreshold));
    }
    
    function test_maximumDonationRate() public {
        uint256 swapAmount = 1 ether;
        
        // Test with maximum allowed donation rate
        uint256 maxDonation = mockHook.calculateDonation(swapAmount, MAX_DONATION_BPS);
        uint256 expectedMaxDonation = (swapAmount * MAX_DONATION_BPS) / DONATION_DENOMINATOR;
        
        assertEq(maxDonation, expectedMaxDonation);
        assertTrue(maxDonation <= swapAmount); // Should never exceed swap amount
    }
    
    function test_zeroDonationRate() public {
        uint256 swapAmount = 1 ether;
        
        // Test with zero donation rate
        uint256 donation = mockHook.calculateDonation(swapAmount, 0);
        
        assertEq(donation, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTREME VALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_nearMaxUint256Values() public {
        // Test with very large but valid values
        uint256 largeAmount = type(uint256).max / DONATION_DENOMINATOR; // Prevent overflow
        uint256 donation = mockHook.calculateDonation(largeAmount, 1); // Minimal rate
        
        assertEq(donation, largeAmount / DONATION_DENOMINATOR);
    }
    
    function test_precisionLimits() public {
        // Test precision at various scales
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 1;
        testAmounts[1] = 1000;
        testAmounts[2] = 1_000_000;
        testAmounts[3] = 1 ether;
        testAmounts[4] = 1000 ether;
        
        for (uint i = 0; i < testAmounts.length; i++) {
            uint256 donation = mockHook.calculateDonation(testAmounts[i], DEFAULT_DONATION_BPS);
            uint256 expected = (testAmounts[i] * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR;
            assertEq(donation, expected);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DELTA CALCULATION EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_deltaCalculation_exactInput() public {
        uint256 swapAmount = 1 ether;
        uint256 donationAmount = (swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR;
        
        // For exact input, delta should be negative (reduce effective swap)
        (int128 deltaAmount0, int128 deltaAmount1) = mockHook.calculateBeforeSwapDelta(
            -int256(swapAmount), // Negative indicates exact input
            donationAmount
        );
        
        // Delta amount0 should be negative donation amount
        assertEq(deltaAmount0, -donationAmount.toInt128());
        assertEq(deltaAmount1, 0);
    }
    
    function test_deltaCalculation_exactOutput() public {
        uint256 swapAmount = 1 ether;
        uint256 donationAmount = (swapAmount * DEFAULT_DONATION_BPS) / DONATION_DENOMINATOR;
        
        // For exact output, delta should be positive (increase input requirement)
        (int128 deltaAmount0, int128 deltaAmount1) = mockHook.calculateBeforeSwapDelta(
            int256(swapAmount), // Positive indicates exact output
            donationAmount
        );
        
        // Delta amount0 should be positive donation amount
        assertEq(deltaAmount0, donationAmount.toInt128());
        assertEq(deltaAmount1, 0);
    }
    
    function test_deltaCalculation_zeroDonation() public {
        uint256 swapAmount = 1 ether;
        
        (int128 deltaAmount0, int128 deltaAmount1) = mockHook.calculateBeforeSwapDelta(
            -int256(swapAmount),
            0 // Zero donation
        );
        
        // Should return zero delta
        assertEq(deltaAmount0, 0);
        assertEq(deltaAmount1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE PATTERN EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_donationStorage_maxValues() public {
        // Test storage with maximum valid values
        uint256 maxAmount = (1 << 96) - 1; // Maximum amount that fits in 96 bits
        address testUser = address(uint160(type(uint160).max)); // Maximum address
        
        bytes32 packed = mockHook.packDonationInfo(maxAmount, testUser);
        (uint256 unpackedAmount, address unpackedUser) = mockHook.unpackDonationInfo(packed);
        
        assertEq(unpackedAmount, maxAmount);
        assertEq(unpackedUser, testUser);
    }
    
    function test_donationStorage_minValues() public {
        // Test storage with minimum values
        uint256 minAmount = 0;
        address testUser = address(0);
        
        bytes32 packed = mockHook.packDonationInfo(minAmount, testUser);
        (uint256 unpackedAmount, address unpackedUser) = mockHook.unpackDonationInfo(packed);
        
        assertEq(unpackedAmount, minAmount);
        assertEq(unpackedUser, testUser);
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_governance_immediateUpdate() public {
        // Test updating donation rate immediately after previous update
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 2000);
        
        // Should fail in same block
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, 3000);
        
        // Should work in next block
        vm.roll(block.number + 1);
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 3000);
        
        assertEq(mockHook.getPoolDonationRate(testPoolId), 3000);
    }
    
    function test_governance_timeLockEdge() public {
        address newManager = makeAddr("newManager");
        
        vm.prank(donationManager);
        mockHook.initiateDonationManagerUpdate(newManager);
        
        uint256 unlockTime = block.timestamp + 1 days;
        
        // Should fail exactly at unlock time minus 1 second
        vm.warp(unlockTime - 1);
        vm.expectRevert();
        mockHook.completeDonationManagerUpdate();
        
        // Should succeed exactly at unlock time
        vm.warp(unlockTime);
        mockHook.completeDonationManagerUpdate();
        
        assertEq(mockHook.donationManager(), newManager);
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK DATA EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_hookData_addressBoundaries() public {
        // Test with address at boundaries
        address[] memory testAddresses = new address[](3);
        testAddresses[0] = address(0);
        testAddresses[1] = address(1);
        testAddresses[2] = address(type(uint160).max);
        
        for (uint i = 0; i < testAddresses.length; i++) {
            bytes memory hookData = abi.encode(testAddresses[i]);
            address parsed = mockHook.parseUserAddress(hookData);
            assertEq(parsed, testAddresses[i]);
        }
    }
    
    function test_hookData_exactLength() public {
        // Test with exactly 32 bytes
        bytes memory exactData = new bytes(32);
        // Fill with some pattern
        for (uint i = 0; i < 32; i++) {
            exactData[i] = bytes1(uint8(i));
        }
        
        // Should not revert (though may not decode to valid address)
        vm.expectRevert(); // Will revert due to invalid encoding, but length check passes
        mockHook.parseUserAddress(exactData);
    }

    /*//////////////////////////////////////////////////////////////
                        RATE LIMITING EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_rateLimiting_blockBoundary() public {
        uint256 startBlock = block.number;
        
        // Update at block N
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 1000);
        assertEq(mockHook.getLastUpdateBlock(testPoolId), startBlock);
        
        // Should fail at same block
        vm.prank(donationManager);
        vm.expectRevert();
        mockHook.setPoolDonationRate(testPoolId, 2000);
        
        // Should succeed at block N+1
        vm.roll(startBlock + 1);
        vm.prank(donationManager);
        mockHook.setPoolDonationRate(testPoolId, 2000);
        assertEq(mockHook.getLastUpdateBlock(testPoolId), startBlock + 1);
    }
    
    function test_rateLimiting_multipleBlocks() public {
        uint256[] memory rates = new uint256[](5);
        rates[0] = 1000;
        rates[1] = 2000;
        rates[2] = 3000;
        rates[3] = 1500;
        rates[4] = 500;
        
        for (uint i = 0; i < rates.length; i++) {
            vm.prank(donationManager);
            mockHook.setPoolDonationRate(testPoolId, rates[i]);
            assertEq(mockHook.getPoolDonationRate(testPoolId), rates[i]);
            
            vm.roll(block.number + 1); // Advance block
        }
    }

    /*//////////////////////////////////////////////////////////////
                        POOL ISOLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_multiplePoolIsolation() public {
        // Create multiple pools with different configurations
        PoolKey[] memory keys = new PoolKey[](3);
        PoolId[] memory ids = new PoolId[](3);
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1000;
        rates[1] = 2000;
        rates[2] = 5000;
        
        for (uint i = 0; i < 3; i++) {
            keys[i] = PoolKey({
                currency0: i % 2 == 0 ? currency0 : currency1,
                currency1: i % 2 == 0 ? currency1 : currency0,
                fee: uint24(500 + i * 1000),
                tickSpacing: int24(int256(10 + i * 50)),
                hooks: IHooks(address(0))
            });
            ids[i] = keys[i].toId();
            
            vm.prank(donationManager);
            mockHook.setPoolDonationRate(ids[i], rates[i]);
            vm.roll(block.number + 1);
        }
        
        // Verify isolation
        for (uint i = 0; i < 3; i++) {
            assertEq(mockHook.getPoolDonationRate(ids[i]), rates[i]);
        }
    }
}

/// @notice Mock hook contract for testing edge cases and boundary conditions
contract MockEdgeCaseTempleHook {
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
    }
    
    function initiateDonationManagerUpdate(address newManager) external onlyDonationManager {
        if (newManager == address(0)) revert InvalidAddress();
        
        pendingDonationManager = newManager;
        governanceUpdateTime = block.timestamp + GOVERNANCE_DELAY;
    }
    
    function completeDonationManagerUpdate() external {
        if (block.timestamp < governanceUpdateTime) revert GovernanceDelay();
        if (pendingDonationManager == address(0)) revert InvalidAddress();
        
        address oldManager = donationManager;
        donationManager = pendingDonationManager;
        pendingDonationManager = address(0);
        governanceUpdateTime = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function calculateDonation(uint256 swapAmount, uint256 donationBps) external pure returns (uint256) {
        return (swapAmount * donationBps) / DONATION_DENOMINATOR;
    }
    
    function calculateBeforeSwapDelta(int256 amountSpecified, uint256 donationAmount) 
        external 
        pure 
        returns (int128, int128) 
    {
        if (donationAmount == 0) {
            return (0, 0);
        }
        
        if (amountSpecified < 0) {
            // Exact input: reduce effective swap amount by donation
            return (-int128(int256(donationAmount)), 0);
        } else {
            // Exact output: increase input requirement by donation
            return (int128(int256(donationAmount)), 0);
        }
    }
    
    function parseUserAddress(bytes calldata hookData) external pure returns (address) {
        if (hookData.length != 32) revert InvalidHookData();
        return abi.decode(hookData, (address));
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
    
    function getLastUpdateBlock(PoolId poolId) external view returns (uint256) {
        return poolConfigs[poolId].lastUpdateBlock;
    }
    
    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }
}