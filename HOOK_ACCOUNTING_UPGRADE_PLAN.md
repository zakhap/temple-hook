# Temple Hook Accounting Upgrade Plan

## Overview

This plan outlines the upgrade of Temple Hook implementations to use Uniswap V4's proper mint/burn/take accounting system, based on learnings from Clanker's implementation. Since contracts are not yet deployed, we can implement these improvements directly without migration complexity.

## Current Issues

### SimpleTempleHook Issues
- Uses outdated delta accounting that doesn't properly settle
- Recalculates donation amount in both `_beforeSwap` and `_afterSwap`
- May have currency settlement issues
- Inefficient gas usage

### OptimizedTempleHook Issues  
- Complex direction-aware delta calculation that was recently fixed
- Still uses older accounting patterns
- Could benefit from cleaner mint/burn/take flow
- Missing proper quoter integration considerations

## Target Architecture

### New Accounting Flow
1. **_beforeSwap**: Calculate donation, mint credits to hook, return BeforeSwapDelta
2. **_afterSwap**: Burn credits, take tokens to charity, emit event
3. **User Experience**: Quoter includes all fees in quotes automatically

### Key Benefits
- ✅ Proper delta settlement (no more CurrencyNotSettled errors)
- ✅ Cleaner code with single donation calculation
- ✅ Immediate charity transfers with user attribution
- ✅ Better quoter integration
- ✅ More efficient gas usage
- ✅ Follows Uniswap V4 best practices

---

## SimpleTempleHook Upgrade Plan

### Phase 1: Update _beforeSwap

**Current Code Issues:**
```solidity
// Current problematic approach
BeforeSwapDelta returnDelta = toBeforeSwapDelta(
    int128(int256(donationAmount)), // Hook receives donation amount
    0                               // No change to unspecified token
);
```

**New Implementation:**
```solidity
function _beforeSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
) internal override returns (bytes4, BeforeSwapDelta, uint24) {
    // Extract user address from hookData
    address user = parseHookData(hookData);
    
    // Calculate donation amount
    uint256 swapAmount = params.amountSpecified < 0
        ? uint256(-params.amountSpecified)
        : uint256(params.amountSpecified);
    
    uint256 donationAmount = (swapAmount * _hookDonationPercentage) / DONATION_DENOMINATOR;
    
    // Determine donation currency
    Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
    
    // MINT: Credit hook with donation amount
    poolManager.mint(address(this), donationCurrency.toId(), donationAmount);
    
    // BEFORE_SWAP_DELTA: Tell PoolManager to charge user for this credit
    BeforeSwapDelta delta = toBeforeSwapDelta(int128(donationAmount), 0);
    
    // Store donation info for afterSwap (gas-efficient storage)
    _storeDonationInfo(key.toId(), donationAmount, donationCurrency, user);
    
    return (BaseHook.beforeSwap.selector, delta, 0);
}
```

### Phase 2: Update _afterSwap

**Current Code Issues:**
```solidity
// Current: Recalculates donation amount (inefficient)
uint256 donationAmount = (swapAmount * _hookDonationPercentage) / DONATION_DENOMINATOR;
poolManager.take(donationCurrency, QUBIT_ADDRESS, donationAmount);
```

**New Implementation:**
```solidity
function _afterSwap(
    address sender,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta delta,
    bytes calldata hookData
) internal override returns (bytes4, int128) {
    // Retrieve stored donation info from beforeSwap
    (uint256 donationAmount, Currency donationCurrency, address user) = _getDonationInfo(key.toId());
    
    if (donationAmount > 0) {
        // BURN: Remove credits from hook's account
        poolManager.burn(address(this), donationCurrency.toId(), donationAmount);
        
        // TAKE: Transfer actual tokens to charity
        poolManager.take(donationCurrency, QUBIT_ADDRESS, donationAmount);
        
        // EMIT: Event with user attribution
        emit CharitableDonationTaken(user, key.toId(), donationCurrency, donationAmount);
        
        // Clean up storage
        _clearDonationInfo(key.toId());
    }
    
    return (BaseHook.afterSwap.selector, 0);
}
```

### Phase 3: Add Storage Helper Functions

**New Functions Needed:**
```solidity
// Efficient storage for donation info between hooks
struct DonationInfo {
    uint256 amount;
    Currency currency;
    address user;
}

mapping(PoolId => DonationInfo) private _donationStorage;

function _storeDonationInfo(
    PoolId poolId,
    uint256 amount,
    Currency currency,
    address user
) internal {
    _donationStorage[poolId] = DonationInfo(amount, currency, user);
}

function _getDonationInfo(PoolId poolId) internal view returns (
    uint256 amount,
    Currency currency,
    address user
) {
    DonationInfo memory info = _donationStorage[poolId];
    return (info.amount, info.currency, info.user);
}

function _clearDonationInfo(PoolId poolId) internal {
    delete _donationStorage[poolId];
}
```

### Phase 4: Update Hook Permissions

**Ensure proper permissions:**
```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
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
        beforeSwapReturnDelta: true,      // Required for BeforeSwapDelta
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

---

## OptimizedTempleHook Upgrade Plan

### Phase 1: Simplify _beforeSwap

**Current Code Issues:**
```solidity
// Current complex direction-aware delta calculation
if (params.amountSpecified < 0) {
    if (params.zeroForOne) {
        delta = toBeforeSwapDelta(donationAmount.toInt128(), 0);
    } else {
        delta = toBeforeSwapDelta(0, donationAmount.toInt128());
    }
} else {
    // More complex logic...
}
```

**New Implementation:**
```solidity
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
    
    // Calculate donation amount
    uint256 swapAmount = params.amountSpecified < 0 
        ? uint256(-params.amountSpecified)
        : uint256(params.amountSpecified);
    
    uint256 donationAmount = _calculateDonation(swapAmount, config.donationBps);
    
    // Skip tiny donations
    if (donationAmount < MIN_DONATION_AMOUNT) {
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    
    // Determine donation currency (always input currency)
    Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
    
    // MINT: Credit hook with donation
    poolManager.mint(address(this), donationCurrency.toId(), donationAmount);
    
    // BEFORE_SWAP_DELTA: Simple - always take from input currency
    BeforeSwapDelta delta = toBeforeSwapDelta(donationAmount.toInt128(), 0);
    
    // Store donation info for afterSwap
    _storeDonationInfo(poolId, donationAmount, donationCurrency, user);
    
    return (BaseHook.beforeSwap.selector, delta, 0);
}
```

### Phase 2: Simplify _afterSwap

**Current Code Issues:**
```solidity
// Current: Complex retrieval and currency determination
(uint256 donationAmount, address user) = _getDonationInfo(poolId);
Currency donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
```

**New Implementation:**
```solidity
function _afterSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    BalanceDelta,
    bytes calldata
) internal override returns (bytes4, int128) {
    PoolId poolId = key.toId();
    
    // Retrieve stored donation info (includes currency)
    (uint256 donationAmount, Currency donationCurrency, address user) = _getDonationInfo(poolId);
    
    if (donationAmount > 0) {
        // BURN: Remove credits from hook
        poolManager.burn(address(this), donationCurrency.toId(), donationAmount);
        
        // TAKE: Transfer to charity
        poolManager.take(donationCurrency, CHARITY_ADDRESS, donationAmount);
        
        // EMIT: Enhanced event with more details
        emit CharitableDonationCollected(
            user,
            poolId,
            donationCurrency,
            donationAmount,
            params.amountSpecified < 0 
                ? uint256(-params.amountSpecified)
                : uint256(params.amountSpecified)
        );
        
        // Clean up storage
        _clearDonationInfo(poolId);
    }
    
    return (BaseHook.afterSwap.selector, 0);
}
```

### Phase 3: Update Storage System

**Replace current storage with enhanced version:**
```solidity
// Remove old storage
// mapping(PoolId => uint256) private _donationAmounts;
// mapping(PoolId => address) private _donationUsers;

// Add new unified storage
struct DonationInfo {
    uint256 amount;
    Currency currency;
    address user;
}

mapping(PoolId => DonationInfo) private _donationStorage;

// Update helper functions to include currency
function _storeDonationInfo(
    PoolId poolId,
    uint256 amount,
    Currency currency,
    address user
) internal {
    _donationStorage[poolId] = DonationInfo(amount, currency, user);
}

function _getDonationInfo(PoolId poolId) internal view returns (
    uint256 amount,
    Currency currency,
    address user
) {
    DonationInfo memory info = _donationStorage[poolId];
    return (info.amount, info.currency, info.user);
}

function _clearDonationInfo(PoolId poolId) internal {
    delete _donationStorage[poolId];
}
```

---

## Testing Strategy

### Phase 1: Unit Tests

**Test Cases to Add:**
1. **Delta Settlement**: Verify transactions don't fail with CurrencyNotSettled
2. **Mint/Burn/Take Flow**: Test the three-step accounting process
3. **User Attribution**: Verify correct user addresses in events
4. **Currency Handling**: Test both directions (ETH→Temple, Temple→ETH)
5. **Edge Cases**: Zero donations, minimum amounts, paused states

### Phase 2: Integration Tests

**Test Scenarios:**
1. **Quoter Integration**: Verify quoter includes hook fees in quotes
2. **Multiple Swaps**: Test sequential swaps with proper accounting
3. **Gas Optimization**: Compare gas usage before/after
4. **Error Handling**: Test failure cases and rollbacks

### Phase 3: Deployment Tests

**Sepolia Fork Testing:**
1. Deploy updated hooks
2. Test with actual swap router
3. Verify charity receives donations
4. Test with different swap amounts and directions
5. Validate event emissions

---


## Success Metrics

### Technical Metrics
- ✅ Zero CurrencyNotSettled errors
- ✅ Proper delta settlement in all cases
- ✅ Gas usage optimization (target: 10-20% reduction)
- ✅ Event emission accuracy (100% user attribution)

### Product Success Metrics
- ✅ Accurate quoter integration (fees included in quotes)
- ✅ Immediate charity transfers with proper attribution
- ✅ No failed transactions due to accounting
- ✅ Regulatory compliance through proper event emission
- ✅ Enhanced user experience and trust

---

## Timeline

### Week 1: SimpleTempleHook Upgrade
- Implement new accounting flow
- Add storage helpers
- Update permissions
- Unit testing

### Week 2: OptimizedTempleHook Upgrade  
- Simplify delta calculations
- Implement mint/burn/take flow
- Enhanced storage system
- Integration testing

### Week 3: Testing & Validation
- Comprehensive test suite
- Sepolia fork testing
- Gas optimization
- Security review

### Week 4: Deployment Preparation
- Finalize deployment scripts
- Prepare testnet deployment
- Final security review
- Production deployment planning

---

## Risk Mitigation

### Technical Risks
- **Currency Settlement**: Extensive testing of all swap directions to prevent CurrencyNotSettled errors
- **Gas Optimization**: Benchmark gas usage to ensure efficiency improvements
- **Event Accuracy**: Validate all user attribution scenarios for regulatory compliance
- **State Management**: Proper storage and cleanup of donation info between hook calls

### Mitigation Strategies
- Comprehensive test coverage (>95%)
- Thorough testing on testnets before mainnet deployment
- Code review and security audit
- Proper event emission for regulatory compliance
- Emergency pause mechanisms in production

---

## Conclusion

This upgrade will implement both Temple Hook contracts using Uniswap V4's proper accounting system, following proven patterns from Clanker's implementation. The result will be reliable, efficient charitable donation mechanisms with proper regulatory compliance.

The key benefits include proper delta settlement, cleaner code architecture, immediate charity transfers with user attribution, and seamless integration with the Uniswap V4 ecosystem including quoters and frontends.