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
import {TempleToken} from "./TempleToken.sol";

/**
 * @title SimpleTempleHook
 * @notice A Uniswap v4 hook that collects charitable donations from swap transactions
 * @dev This hook implements a fee mechanism that takes a small percentage (default 0.01%)
 * from each swap transaction and sends it to a designated charity address (QUBIT_ADDRESS).
 * 
 * The hook uses Uniswap v4's custom accounting system to:
 * 1. Calculate a donation amount based on the swap size
 * 2. Collect the donation using BeforeSwapDelta mechanism
 * 3. Track all donations through events for transparency
 * 
 * The donation percentage can be adjusted by the donation manager, up to a maximum of 1%.
 * The hook requires hookData to contain the end user's address for proper attribution.
 */
contract SimpleTempleHook is BaseHook {
    address internal immutable QUBIT_ADDRESS;
    address private _donationManager;
    uint256 private _hookDonationPercentage = 10; // 0.01% default donation
    uint256 private constant DONATION_DENOMINATOR = 100000;

    event CharitableDonationTaken(
      address indexed user,
      PoolId indexed poolId,
      Currency indexed donationCurrency,
      uint256 donationAmount
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
        require(newDonationPercentage <= 1000, "Donation too high"); // Max 1% (1000/100000)
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


    function getDonationManager() external view returns (address) {
        return _donationManager;
    }

    function getHookDonationPercentage() external view returns (uint256) {
        return _hookDonationPercentage;
    }

    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }


    // do i need this?
    function getHookData(address user) public pure returns (bytes memory) {
        return abi.encode(user);
    }

    // gets user address from HookData, for emitting event
    function parseHookData(
        bytes calldata data
    ) public pure returns (address user) {
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
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // take fee, emit event
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Extract the user address from hookData
        address user = parseHookData(hookData);
        
        // Calculate absolute swap amount (convert negative to positive)
        uint256 swapAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        
        // Calculate donation amount based on percentage
        uint256 donationAmount = (swapAmount * _hookDonationPercentage) / DONATION_DENOMINATOR;
        
        // Determine which currency the donation should be taken in
        Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        
        // Take the donation by creating a debt for our hook in the specified currency
        poolManager.take(donationCurrency, QUBIT_ADDRESS, donationAmount);
        
        // Create BeforeSwapDelta to transfer the hook's delta to the swap router
        BeforeSwapDelta returnDelta = toBeforeSwapDelta(
            int128(int256(donationAmount)), // Specified delta (donation amount)
            0                               // Unspecified delta (no change)
        );
        
        // Add event emission for donation collection tracking
        emit CharitableDonationTaken(user, key.toId(), donationCurrency, donationAmount);
        
        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }
}