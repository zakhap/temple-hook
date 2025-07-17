// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

/**
 * @title OptimizedTempleHook
 * @notice Gas-optimized, secure charitable donation hook for Uniswap v4
 * @dev Implements proper delta accounting with security guardrails
 */
contract OptimizedTempleHook is BaseHook {
    using SafeCast for uint256;
    using SafeCast for int256;
    using PoolIdLibrary for PoolKey;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    address public immutable CHARITY_ADDRESS;
    uint256 private constant DONATION_DENOMINATOR = 1_000_000; // 1M for precision
    uint256 private constant MAX_DONATION_BPS = 10_000; // 1% max (10,000 / 1M)
    uint256 private constant MIN_DONATION_AMOUNT = 1000; // Minimum donation to avoid dust
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    struct DonationConfig {
        uint128 donationBps; // Basis points (0-10,000)
        uint128 lastUpdateBlock; // Rate limiting
    }
    
    mapping(PoolId => DonationConfig) public poolConfigs;
    
    // Governance
    address public donationManager;
    address public pendingDonationManager;
    uint256 public constant GOVERNANCE_DELAY = 1 days;
    uint256 public governanceUpdateTime;
    
    // Emergency controls
    bool public emergencyPaused;
    address public guardian;
    
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
    event DonationManagerUpdateInitiated(address newManager, uint256 effectiveTime);
    event DonationManagerUpdated(address oldManager, address newManager);
    event EmergencyPaused(bool paused);
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error Unauthorized();
    error InvalidDonationRate();
    error InvalidAddress();
    error EmergencyPausedError();
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
    
    modifier notPaused() {
        if (emergencyPaused) revert EmergencyPausedError();
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IPoolManager _poolManager,
        address _charityAddress,
        address _donationManager,
        address _guardian
    ) BaseHook(_poolManager) {
        if (_charityAddress == address(0)) revert InvalidAddress();
        if (_donationManager == address(0)) revert InvalidAddress();
        if (_guardian == address(0)) revert InvalidAddress();
        
        CHARITY_ADDRESS = _charityAddress;
        donationManager = _donationManager;
        guardian = _guardian;
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS
    //////////////////////////////////////////////////////////////*/
    
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true, // Set default config
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24
    ) internal override returns (bytes4) {
        // Set default 2% donation rate for new pools
        PoolId poolId = key.toId();
        poolConfigs[poolId] = DonationConfig({
            donationBps: 20000, // 2%
            lastUpdateBlock: uint128(block.number)
        });
        
        emit DonationConfigUpdated(poolId, 20000);
        return BaseHook.afterInitialize.selector;
    }
    
    function _beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override notPaused returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        DonationConfig memory config = poolConfigs[poolId];
        
        // Skip if no donation configured
        if (config.donationBps == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Parse user address safely
        address user = _parseUserAddress(hookData);
        
        // Calculate donation on INPUT token (always the specified token for exactInput swaps)
        uint256 swapAmount = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
            
        uint256 donationAmount = _calculateDonation(swapAmount, config.donationBps);
        
        // Skip tiny donations to avoid dust
        if (donationAmount < MIN_DONATION_AMOUNT) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Calculate delta for donation collection
        BeforeSwapDelta delta;
        if (params.amountSpecified < 0) {
            // Exact input: take donation from the input currency
            if (params.zeroForOne) {
                // ETH->Temple: take donation from ETH (currency0)
                delta = toBeforeSwapDelta(donationAmount.toInt128(), 0);
            } else {
                // Temple->ETH: take donation from Temple (currency1) 
                delta = toBeforeSwapDelta(0, donationAmount.toInt128());
            }
        } else {
            // Exact output: increase input requirement by donation
            if (params.zeroForOne) {
                // ETH->Temple: require more ETH input
                delta = toBeforeSwapDelta(donationAmount.toInt128(), 0);
            } else {
                // Temple->ETH: require more Temple input
                delta = toBeforeSwapDelta(0, donationAmount.toInt128());
            }
        }
        
        // Store donation info for afterSwap (gas-efficient)
        _storeDonationInfo(poolId, donationAmount, user);
        
        return (BaseHook.beforeSwap.selector, delta, 0);
    }
    
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        
        // Retrieve stored donation info
        (uint256 donationAmount, address user) = _getDonationInfo(poolId);
        
        if (donationAmount > 0) {
            // Determine donation currency (always input token)
            Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
            
            // Transfer donation to charity
            poolManager.take(donationCurrency, CHARITY_ADDRESS, donationAmount);
            
            // Clean up storage
            _clearDonationInfo(poolId);
            
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
        
        return (BaseHook.afterSwap.selector, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE
    //////////////////////////////////////////////////////////////*/
    
    function setPoolDonationRate(
        PoolId poolId,
        uint256 newDonationBps
    ) external onlyDonationManager {
        if (newDonationBps > MAX_DONATION_BPS) revert InvalidDonationRate();
        
        DonationConfig storage config = poolConfigs[poolId];
        
        // Rate limiting: max one update per block
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
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    
    function _calculateDonation(
        uint256 swapAmount,
        uint256 donationBps
    ) internal pure returns (uint256) {
        return (swapAmount * donationBps) / DONATION_DENOMINATOR;
    }
    
    function _parseUserAddress(bytes calldata hookData) internal pure returns (address) {
        if (hookData.length != 32) revert InvalidHookData();
        return abi.decode(hookData, (address));
    }
    
    // Efficient storage pattern for donation info
    mapping(PoolId => bytes32) private _donationStorage;
    
    function _storeDonationInfo(PoolId poolId, uint256 amount, address user) private {
        _donationStorage[poolId] = bytes32(
            (uint256(uint160(user)) << 96) | amount
        );
    }
    
    function _getDonationInfo(PoolId poolId) private view returns (uint256 amount, address user) {
        bytes32 data = _donationStorage[poolId];
        amount = uint256(data) & ((1 << 96) - 1);
        user = address(uint160(uint256(data) >> 96));
    }
    
    function _clearDonationInfo(PoolId poolId) private {
        delete _donationStorage[poolId];
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
    
    function getHookData(address user) external pure returns (bytes memory) {
        return abi.encode(user);
    }
}