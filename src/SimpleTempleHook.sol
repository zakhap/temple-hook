// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {TempleToken} from "./TempleToken.sol";

/**
 * @title SimpleTempleHook
 * @notice A Uniswap v4 hook that collects charitable donations from swap transactions
 * @dev This hook implements a fee mechanism that takes a small percentage (default 0.01%)
 * from each swap transaction and sends it to a designated charity address (QUBIT_ADDRESS).
 * 
 * The hook uses Uniswap v4's delta accounting system properly:
 * 1. beforeSwap: Calculate donation amount and return BeforeSwapDelta indicating hook receives donation
 * 2. afterSwap: Transfer the collected donation to the charity address using poolManager.take()
 * 3. Event emission for full transparency of all donations
 * 
 * This approach ensures users only pay the intended donation amount (no double deduction)
 * while the charity receives the donations through proper Uniswap v4 accounting.
 * 
 * The donation percentage can be adjusted by the donation manager, up to a maximum of 1%.
 * The hook requires hookData to contain the end user's address for proper attribution.
 */
contract SimpleTempleHook is BaseHook {
    using CurrencyLibrary for Currency;

    address internal immutable QUBIT_ADDRESS;
    string internal constant QUBIT_EIN = "46-0659995"; // Charity's EIN for transparency
    string internal constant TAX_RECEIPT_STATEMENT = "No goods or services were rendered or performed in exchange for this contribution.";
    address private _donationManager;
    uint256 private _hookDonationPercentage = 1; // 0.01% default donation (1/100000)
    uint256 private constant DONATION_DENOMINATOR = 100000;

    // Temporary storage for donation info between hooks
    uint256 private _tempDonationAmount;
    Currency private _tempDonationCurrency;
    address private _tempDonationUser;

    event CharitableDonationTaken(
      address indexed user,
      PoolId indexed poolId,
      Currency indexed donationCurrency,
      uint256 donationAmount,
      string charityEIN,
      string taxReceiptStatement,
      uint256 timestamp
    );
    event DonationPercentageUpdated(uint256 newDonationPercentage);
    event DonationManagerUpdated(address newDonationManager);


    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        QUBIT_ADDRESS = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720; // SET THIS CORRECTLY, is set to anvil (9)
        _donationManager = msg.sender; // Set deployer as initial donation manager
    }

    modifier onlyDonationManager() {
        require(msg.sender == _donationManager, "Only donation manager");
        _;
    }

    // Function to update donation percentage (restricted to donation manager)
    function setDonationPercentage(uint256 newDonationPercentage) external onlyDonationManager {
        require(newDonationPercentage <= 3000, "Donation too high"); // Max 3% (3000/100000)
        _hookDonationPercentage = newDonationPercentage;
        emit DonationPercentageUpdated(newDonationPercentage);
    }

    // Function to transfer donation manager role
    function setDonationManager(address newDonationManager) external onlyDonationManager {
        require(newDonationManager != address(0), "Zero address");
        _donationManager = newDonationManager;
        emit DonationManagerUpdated(newDonationManager);
    }

    function qubitAddress() external view returns (address) {
        return QUBIT_ADDRESS;
    }

    function qubitEIN() external pure returns (string memory) {
        return QUBIT_EIN;
    }

    function getDonationManager() external view returns (address) {
        return _donationManager;
    }

    function getHookDonationPercentage() external view returns (uint256) {
        return _hookDonationPercentage;
    }

    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }



    // gets user address from HookData, for emitting event
    function parseHookData(
        bytes calldata data
    ) public pure returns (address user) {
        require(data.length > 0, "Empty hook data");
        return abi.decode(data, (address));
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
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

    // Collect donation using mint/burn/take pattern
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Extract user address from hookData for event (optional)
        address user = hookData.length >= 20 ? abi.decode(hookData, (address)) : sender;
        
        // Calculate donation based on swap amount
        uint256 swapAmount = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified) 
            : uint256(params.amountSpecified);
        uint256 donationAmount = (swapAmount * _hookDonationPercentage) / DONATION_DENOMINATOR;
        
        // Only proceed if donation amount is meaningful
        if (donationAmount == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        
        // Determine donation currency based on swap direction
        // Take donation from the input currency (what user is paying)
        Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        
        // MINT: Credit hook with donation amount
        poolManager.mint(address(this), donationCurrency.toId(), donationAmount);
        
        // Create BeforeSwapDelta to tell PoolManager to charge user for this credit
        BeforeSwapDelta returnDelta = toBeforeSwapDelta(
            int128(int256(donationAmount)), // Hook receives donation amount
            0                               // No change to unspecified token
        );
        
        // Store donation info for afterSwap (simple approach)
        _tempDonationAmount = donationAmount;
        _tempDonationCurrency = donationCurrency;
        _tempDonationUser = user;
        
        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    // Transfer collected donations to charity after swap
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Only proceed if we have a donation to process
        if (_tempDonationAmount > 0) {
            // BURN: Remove credits from hook's account
            poolManager.burn(address(this), _tempDonationCurrency.toId(), _tempDonationAmount);
            
            // TAKE: Transfer actual tokens to charity
            poolManager.take(_tempDonationCurrency, QUBIT_ADDRESS, _tempDonationAmount);

            // EMIT: Event with user attribution, charity EIN, tax receipt statement, and timestamp
            emit CharitableDonationTaken(_tempDonationUser, key.toId(), _tempDonationCurrency, _tempDonationAmount, QUBIT_EIN, TAX_RECEIPT_STATEMENT, block.timestamp);

            // Clean up temporary storage
            _tempDonationAmount = 0;
            _tempDonationCurrency = Currency.wrap(address(0));
            _tempDonationUser = address(0);
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }
}