// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

contract T3MPL3Hook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // QUBIT charity address (Anvil account 9 for testing)
    address public constant QUBIT_ADDRESS = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    
    // 1% donation fee (100/10000 = 1%)
    uint256 public constant DONATION_PERCENTAGE = 100;
    uint256 public constant PERCENTAGE_DENOMINATOR = 10000;

    event CharitableDonationTaken(
        address indexed user,
        PoolId indexed poolId,
        Currency indexed donationCurrency,
        uint256 donationAmount
    );

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
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

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Calculate donation amount from swap
        uint256 swapAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        
        uint256 donationAmount = (swapAmount * DONATION_PERCENTAGE) / PERCENTAGE_DENOMINATOR;
        
        // Determine donation currency (take from input currency)
        Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        
        // Take donation to QUBIT
        poolManager.take(donationCurrency, QUBIT_ADDRESS, donationAmount);
        
        // Create delta to account for the donation
        BeforeSwapDelta returnDelta = toBeforeSwapDelta(
            int128(int256(donationAmount)), // Specified delta (donation amount)
            0                               // Unspecified delta
        );
        
        // Extract user address from hookData for event (optional)
        address user = hookData.length >= 20 ? abi.decode(hookData, (address)) : sender;
        
        emit CharitableDonationTaken(user, key.toId(), donationCurrency, donationAmount);
        
        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }
}
