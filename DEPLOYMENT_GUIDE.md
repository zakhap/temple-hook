# OptimizedTempleHook Deployment Guide

## Quick Setup for Sepolia Fork Testing

### 1. Start Anvil with Sepolia Fork
```bash
anvil --fork-url $SEPOLIA_RPC_URL --chain-id 11155111
```

### 2. Deploy Temple Token
```bash
forge script script/DeployTempleToken.s.sol --rpc-url http://localhost:8545 --broadcast --private-key $PRIVATE_KEY
```
Save the Temple token address from the output.

### 3. Deploy OptimizedTempleHook
```bash
forge script script/DeployOptimizedHook.s.sol --rpc-url http://localhost:8545 --broadcast --private-key $PRIVATE_KEY
```
Save the hook address from the output.

### 4. Set Environment Variables
```bash
export TEMPLE_TOKEN_ADDRESS=<temple_token_address_from_step_2>
export OPTIMIZED_HOOK_ADDRESS=<hook_address_from_step_3>
```

### 5. Create Lopsided Pool
```bash
forge script script/CreateOptimizedPool.s.sol --rpc-url http://localhost:8545 --broadcast --private-key $PRIVATE_KEY
```

## What This Creates

- **Temple Token**: ERC20 with 1M supply
- **OptimizedTempleHook**: Hook with 0.1% default donation rate
- **Lopsided Pool**: 0.01 ETH + 100K Temple tokens
  - Price will appreciate quickly due to imbalance
  - Perfect for testing donation mechanics

## Testing the Hook

After deployment, you can:
1. Perform swaps (ETH → Temple will be cheap, Temple → ETH expensive)
2. Verify donations are collected by the charity address
3. Test governance functions (donation rate changes, emergency pause)
4. Monitor hook events and gas usage

## Key Addresses

All addresses will be logged during deployment. The hook uses:
- **Charity**: `makeAddr("charity")` - receives donations
- **Donation Manager**: Your deployer address - can update rates
- **Guardian**: `makeAddr("guardian")` - emergency controls

## Notes

- Uses existing Sepolia Uniswap v4 infrastructure
- Hook address is mined for correct permissions
- Lopsided liquidity creates interesting price dynamics
- All scripts include detailed console logging