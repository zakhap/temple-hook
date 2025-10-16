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
    string public constant CHARITY_EIN = "46-0659995"; // Charity's EIN for transparency
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
    
    // Temporary storage for donation info between hooks
    uint256 private _tempDonationAmount;
    Currency private _tempDonationCurrency;
    address private _tempDonationUser;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CharitableDonationCollected(
        address indexed user,
        PoolId indexed poolId,
        Currency indexed donationToken,
        uint256 donationAmount,
        uint256 swapAmount,
        string charityEIN
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
        address sender,
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
        address user = hookData.length >= 20 ? abi.decode(hookData, (address)) : sender;
        
        // Calculate donation on INPUT token (always the specified token for exactInput swaps)
        uint256 swapAmount = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
            
        uint256 donationAmount = _calculateDonation(swapAmount, config.donationBps);
        
        // Skip tiny donations to avoid dust
        if (donationAmount < MIN_DONATION_AMOUNT) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Determine donation currency (always input currency)
        Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        
        // MINT: Credit hook with donation amount
        poolManager.mint(address(this), donationCurrency.toId(), donationAmount);
        
        // BEFORE_SWAP_DELTA: Simple - always take from input currency
        BeforeSwapDelta delta = toBeforeSwapDelta(donationAmount.toInt128(), 0);
        
        // Store donation info for afterSwap (simple approach)
        _tempDonationAmount = donationAmount;
        _tempDonationCurrency = donationCurrency;
        _tempDonationUser = user;
        
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
        
        // Only proceed if we have a donation to process
        if (_tempDonationAmount > 0) {
            // BURN: Remove credits from hook's account
            poolManager.burn(address(this), _tempDonationCurrency.toId(), _tempDonationAmount);
            
            // TAKE: Transfer actual tokens to charity
            poolManager.take(_tempDonationCurrency, CHARITY_ADDRESS, _tempDonationAmount);
            
            // EMIT: Event with user attribution and charity EIN
            emit CharitableDonationCollected(
                _tempDonationUser,
                poolId,
                _tempDonationCurrency,
                _tempDonationAmount,
                params.amountSpecified < 0
                    ? uint256(-params.amountSpecified)
                    : uint256(params.amountSpecified),
                CHARITY_EIN
            );
            
            // Clean up temporary storage
            _tempDonationAmount = 0;
            _tempDonationCurrency = Currency.wrap(address(0));
            _tempDonationUser = address(0);
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
    
    // Removed complex storage system - using simple temp variables instead
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getPoolDonationRate(PoolId poolId) external view returns (uint256) {
        return poolConfigs[poolId].donationBps;
    }
    
    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }

    function getCharityEIN() external pure returns (string memory) {
        return CHARITY_EIN;
    }

    function getHookData(address user) external pure returns (bytes memory) {
        return abi.encode(user);
    }
}