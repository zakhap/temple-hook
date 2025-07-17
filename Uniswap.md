# Uniswap v4 Reference Guide for Temple Hook

This document provides comprehensive information about Uniswap v4 concepts and implementation patterns relevant to the Temple Hook project.

## Table of Contents
1. [Core Architecture](#core-architecture)
2. [Hook System](#hook-system)
3. [Delta Accounting](#delta-accounting)
4. [BeforeSwapDelta Mechanism](#beforeswap-delta-mechanism)
5. [Flash Accounting](#flash-accounting)
6. [Hook Fee Implementation](#hook-fee-implementation)
7. [Temple Hook Analysis](#temple-hook-analysis)
8. [Implementation Patterns](#implementation-patterns)
9. [File References](#file-references)

## Core Architecture

### Singleton Design
- **Single Contract Management**: All pool state and operations managed by one contract - `PoolManager.sol`
- **Gas Optimization**: Pool creation is now a state update, not contract deployment
- **Multi-pool Operations**: Swapping through multiple pools no longer requires intermediate token transfers

### Key Features
- **Dynamic Fees**: Pools can adjust fees flexibly, no hardcoded calculation
- **Native ETH Support**: Direct Ether trading without WETH wrapping
- **Custom Accounting**: Developers can alter token amounts during swaps/liquidity modifications
- **Flash Accounting**: Uses EIP-1153 Transient Storage for efficient balance tracking

## Hook System

### Hook Concept
Hooks are external smart contracts that attach to individual pools to customize behavior at specific execution points.

### Core Hook Functions
- `beforeInitialize` / `afterInitialize`: Pool initialization
- `beforeAddLiquidity` / `afterAddLiquidity`: Liquidity modifications  
- `beforeRemoveLiquidity` / `afterRemoveLiquidity`: Liquidity removal
- `beforeSwap` / `afterSwap`: Swap operations
- `beforeDonate` / `afterDonate`: Token donations

### Hook Permissions
Hook contracts specify permissions encoded in their address:
```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeSwap: true,              // Enable beforeSwap hook
        beforeSwapReturnDelta: true,   // Hook returns delta modifications
        // ... other permissions
    });
}
```

### Return Deltas
Enable hooks to modify operation outcomes through custom accounting:
- **Dual Adjustment**: Modify deltas for both hook and swap router
- **Credits/Debts**: Alter what hook and router owe
- **Custom Curves**: Bypass native pricing mechanism
- **Fee Implementation**: Implement custom fee structures

## Delta Accounting

### Basic Concepts
- **Deltas**: Track token obligations as balance changes
- **Negative Deltas**: Tokens owed TO the PoolManager
- **Positive Deltas**: Tokens owed FROM the PoolManager
- **Zero Net Requirement**: All deltas must resolve to zero by transaction end

### Delta Flow Pattern
```
User Operation → Creates Deltas → Hook Modifications → Delta Resolution → Transaction Complete
```

## BeforeSwapDelta Mechanism

### Purpose
`BeforeSwapDelta` allows hooks to modify swap behavior before execution:
- **Specified Token**: Token for which user specifies exact amount
- **Unspecified Token**: Counterpart token determined by pool pricing
- **Gas Optimization**: Packs two int128 values into single int256

### Structure
```solidity
type BeforeSwapDelta is int256;
// Upper 128 bits: specified token delta
// Lower 128 bits: unspecified token delta
```

### Key Functions
```solidity
// Create BeforeSwapDelta
function toBeforeSwapDelta(int128 deltaSpecified, int128 deltaUnspecified) 
    returns (BeforeSwapDelta);

// Extract values
function getSpecifiedDelta(BeforeSwapDelta delta) returns (int128);
function getUnspecifiedDelta(BeforeSwapDelta delta) returns (int128);
```

### Hook Perspective
**Critical**: BeforeSwapDelta is from the HOOK's perspective:
- **Positive delta**: Hook receives tokens
- **Negative delta**: Hook pays tokens
- **Zero delta**: No change for hook

### Usage in PoolManager
```solidity
int256 amountToSwap = params.amountSpecified + beforeSwapDelta.getSpecifiedDelta();
```

## Flash Accounting

### Lock/Unlock Pattern
All pool operations must occur within the unlock context:

1. **Unlock**: `poolManager.unlock(data)`
2. **Execute**: Operations create deltas
3. **Resolve**: All deltas must be settled
4. **Lock**: PoolManager verifies zero net deltas

### Delta Resolution Methods

#### ERC-20 Pattern
```solidity
// For negative deltas (owing tokens)
poolManager.sync(currency);
IERC20(token).transfer(address(poolManager), amount);
poolManager.settle();

// For positive deltas (receiving tokens)  
poolManager.take(currency, recipient, amount);
```

#### ERC-6909 Pattern
```solidity
// For negative deltas
poolManager.burn(currency, address(this), amount);

// For positive deltas
poolManager.mint(currency, address(this), amount);
```

## Hook Fee Implementation

### Recommended Pattern
**Best Practice**: Implement fees using BeforeSwapDelta return values, NOT direct token transfers.

### Correct Fee Implementation
```solidity
function _beforeSwap(
    address,
    PoolKey calldata key,
    IPoolManager.SwapParams calldata params,
    bytes calldata hookData
) internal override returns (bytes4, BeforeSwapDelta, uint24) {
    // Calculate fee amount
    uint256 swapAmount = params.amountSpecified < 0 
        ? uint256(-params.amountSpecified) 
        : uint256(params.amountSpecified);
    uint256 feeAmount = (swapAmount * FEE_PERCENTAGE) / FEE_DENOMINATOR;
    
    // Return BeforeSwapDelta representing fee collection
    BeforeSwapDelta returnDelta = toBeforeSwapDelta(
        int128(int256(feeAmount)), // Hook receives fee amount
        0                          // No change to unspecified token
    );
    
    return (BaseHook.beforeSwap.selector, returnDelta, 0);
}
```

### Fee Collection Process
1. **BeforeSwapDelta Creation**: Indicate fee amount hook will collect
2. **Automatic Settlement**: PoolManager handles the accounting
3. **Hook Balance**: Hook automatically receives the fee
4. **User Payment**: User pays original amount, pool gets reduced amount

## Temple Hook Analysis

### Fixed Implementation ✅

#### Previous Issue (RESOLVED)
The original implementation had double fee collection:
- Used `poolManager.take()` in beforeSwap (took fee directly)
- ALSO returned negative BeforeSwapDelta (reduced swap amount)
- Result: Users paid donation twice

#### Current Correct Implementation
```solidity
// beforeSwap: Indicate hook receives donation via BeforeSwapDelta
BeforeSwapDelta returnDelta = toBeforeSwapDelta(
    int128(int256(donationAmount)), // Hook receives donation amount
    0                               // No unspecified change
);

// afterSwap: Transfer collected donation to charity
poolManager.take(donationCurrency, QUBIT_ADDRESS, donationAmount);
```

**Benefits of this approach:**
- Users pay exactly the intended donation amount (no double deduction)
- Hook properly collects donations through delta accounting
- Charity receives donations via standard transfer mechanism
- Full compatibility with Uniswap v4's accounting system

### Hook Permissions Required
```solidity
beforeSwap: true,              // Enable donation collection
afterSwap: true,               // Enable donation transfer to charity
beforeSwapReturnDelta: true,   // Enable delta return for fees
```

### Deployment Updates Required
⚠️ **Important**: The hook now requires additional permissions (`AFTER_SWAP_FLAG`), so it must be redeployed:
- New hook address will be generated by HookMiner
- Update all deployment scripts with new hook address
- Pool creation scripts need to reference new hook address

## Implementation Patterns

### Hook Development Checklist
1. **Define Permissions**: Set correct hook permissions in `getHookPermissions()`
2. **Implement Hook Functions**: Add required `_beforeSwap()`, `_afterSwap()`, etc.
3. **Handle Delta Returns**: Use BeforeSwapDelta for custom accounting
4. **Test Delta Resolution**: Ensure all deltas net to zero
5. **Deploy with Correct Address**: Use HookMiner for proper address generation

### Common Mistakes
1. **Returning Wrong Selector**: Always return the correct function selector
2. **Incorrect Delta Signs**: Remember hook perspective for delta signs
3. **Missing Delta Resolution**: All deltas must be resolved before transaction end
4. **Double Fee Collection**: Don't use both direct transfers AND delta returns
5. **Wrong Hook Address**: Hook address must encode correct permissions

### Testing Patterns
```solidity
// Test fee collection
uint256 balanceBefore = charity.balance;
performSwap();
uint256 balanceAfter = charity.balance;
assertEq(balanceAfter - balanceBefore, expectedDonation);
```

## File References

### Temple Hook Implementation
- `src/SimpleTempleHook.sol:146` - **ISSUE**: Incorrect fee collection
- `src/SimpleTempleHook.sol:32` - Donation percentage configuration
- `src/SimpleTempleHook.sol:117` - Hook permissions setup
- `script/SimpleTempleHook.s.sol:32` - Hook deployment script

### Uniswap v4 Core References
- `v4-core/src/types/BeforeSwapDelta.sol` - BeforeSwapDelta implementation
- `v4-core/src/types/BalanceDelta.sol` - BalanceDelta implementation  
- `v4-core/src/interfaces/IPoolManager.sol` - PoolManager interface
- `v4-periphery/src/utils/BaseHook.sol` - Hook base contract

### Temple Token & Deployment
- `src/TempleToken.sol:8` - Basic ERC20 implementation
- `script/DeployT3MPL3Token.s.sol:17` - Token deployment script
- `script/CreatePoolWithLiquidity.s.sol` - Pool creation with liquidity
- `script/base/Constants.sol:13-15` - Network configuration

### Documentation Sources
- `/Users/z/Documents/Uniswap_Documentation/BeforeSwapDelta Guide _ Uniswap.txt`
- `/Users/z/Documents/Uniswap_Documentation/Custom Accounting _ Uniswap.txt`
- `/Users/z/Documents/Uniswap_Documentation/Flash Accounting _ Uniswap.txt`
- `/Users/z/Documents/Uniswap_Documentation/Building Your First Hook _ Uniswap.txt`

## Implementation Status

### ✅ Completed
1. **Fixed SimpleTempleHook**: Corrected BeforeSwapDelta logic and donation flow
2. **Updated Hook Permissions**: Added afterSwap functionality
3. **Updated Deployment Script**: Added AFTER_SWAP_FLAG requirement
4. **Created Documentation**: Comprehensive Uniswap v4 reference guide

### 🔄 Next Steps

1. **Redeploy Hook**: Deploy updated hook with new permissions
   ```bash
   forge script script/SimpleTempleHook.s.sol --broadcast --rpc-url <sepolia-rpc>
   ```

2. **Update Script Addresses**: Replace hardcoded hook address in:
   - `script/CreatePoolWithLiquidity.s.sol:35`
   - `script/TestSwapWithDonation.s.sol:21`
   - Any other scripts referencing the old hook address

3. **Test Complete Flow**:
   - Deploy T3MPL3 token
   - Deploy updated SimpleTempleHook
   - Create pool with liquidity
   - Test swaps with donation collection
   - Verify charity receives donations

4. **Validation Tests**:
   - Verify users only pay intended donation amount
   - Confirm charity address receives ETH donations
   - Test edge cases (small swaps, large swaps)
   - Verify event emissions work correctly

---

*This documentation is based on Uniswap v4 official documentation and analysis of the Temple Hook codebase. Always refer to the latest Uniswap v4 documentation for the most current information.*