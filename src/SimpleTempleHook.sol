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
 * @dev This hook implements a fee mechanism that takes a small percentage (default 5%)
 * from each swap transaction and sends it directly to a designated charity address.
 *
 * Implementation follows the official Uniswap v4 custom accounting pattern:
 * 1. beforeSwap: Uses poolManager.take() to transfer donation directly to charity (creates debt for hook)
 * 2. beforeSwap: Returns BeforeSwapDelta to transfer the hook's debt to swap router (user pays the donation)
 * 3. afterSwap: Emits CharitableDonationTaken event for full transparency
 *
 * This pattern ensures:
 * - Charity receives donations immediately in beforeSwap
 * - User pays the donation amount (it's added to their swap cost)
 * - No double accounting or settlement errors
 * - Full event transparency with EIN and tax receipt statement
 *
 * The donation percentage can be adjusted by the donation manager, up to a maximum of 3%.
 * The hookData can optionally contain the end user's address for proper event attribution.
 */
contract SimpleTempleHook is BaseHook {
    using CurrencyLibrary for Currency;

    address private _charityAddress;
    string internal constant QUBIT_EIN = "46-0659995"; // Charity's EIN for transparency
    string internal constant TAX_RECEIPT_STATEMENT = "No goods or services were rendered or performed in exchange for this contribution.";
    address private _donationManager;
    uint256 private _hookDonationPercentage = 5000; // 5% default donation (5000/100000)
    uint256 private constant DONATION_DENOMINATOR = 100000;

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
    event CharityAddressUpdated(address indexed oldCharity, address indexed newCharity);


    constructor(IPoolManager _poolManager, address initialCharity, address initialManager) BaseHook(_poolManager) {
        require(initialCharity != address(0), "Zero charity address");
        require(initialManager != address(0), "Zero manager address");
        _charityAddress = initialCharity;
        _donationManager = initialManager;
    }

    modifier onlyDonationManager() {
        require(msg.sender == _donationManager, "Only donation manager");
        _;
    }

    // Function to update donation percentage (restricted to donation manager)
    function setDonationPercentage(uint256 newDonationPercentage) external onlyDonationManager {
        require(newDonationPercentage <= 30000, "Donation too high"); // Max 30% (30000/100000)
        _hookDonationPercentage = newDonationPercentage;
        emit DonationPercentageUpdated(newDonationPercentage);
    }

    // Function to transfer donation manager role
    function setDonationManager(address newDonationManager) external onlyDonationManager {
        require(newDonationManager != address(0), "Zero address");
        _donationManager = newDonationManager;
        emit DonationManagerUpdated(newDonationManager);
    }

    // Function to update charity address (restricted to donation manager)
    function setCharityAddress(address newCharity) external onlyDonationManager {
        require(newCharity != address(0), "Zero address");
        address oldCharity = _charityAddress;
        _charityAddress = newCharity;
        emit CharityAddressUpdated(oldCharity, newCharity);
    }

    function charityAddress() external view returns (address) {
        return _charityAddress;
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
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // Collect donation using afterSwap pattern (calculates fee from actual output)
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Extract user address from hookData for event (optional)
        address user = hookData.length >= 20 ? abi.decode(hookData, (address)) : sender;

        // Determine which currency is the output (unspecified for exactInput, specified for exactOutput)
        bool outputIsToken0 = params.zeroForOne ? false : true;

        // Get the output amount from the delta
        int256 outputAmount = outputIsToken0 ? delta.amount0() : delta.amount1();

        // Output amount is positive (pool owes user), we need the absolute value
        if (outputAmount <= 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Calculate donation as percentage of actual output
        uint256 donationAmount = (uint256(outputAmount) * _hookDonationPercentage) / DONATION_DENOMINATOR;

        // Only proceed if donation amount is meaningful
        if (donationAmount == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Ensure donation fits in int128
        require(donationAmount <= uint256(uint128(type(int128).max)), "Donation too large");

        // Determine output currency for the donation
        Currency feeCurrency = outputIsToken0 ? key.currency0 : key.currency1;

        // TAKE: Collect the donation from pool and send directly to charity
        poolManager.take(feeCurrency, _charityAddress, donationAmount);

        // EMIT: Event with user attribution, charity EIN, tax receipt statement, and timestamp
        emit CharitableDonationTaken(
            user,
            key.toId(),
            feeCurrency,
            donationAmount,
            QUBIT_EIN,
            TAX_RECEIPT_STATEMENT,
            block.timestamp
        );

        // Return the donation amount as int128
        // This tells the PoolManager that the hook took this amount as a fee
        return (BaseHook.afterSwap.selector, int128(int256(donationAmount)));
    }
}