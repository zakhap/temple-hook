# Base Mainnet Deployment Cost Estimate

## Gas Usage from Test Deployment

From our local Base fork deployment, we observed:

### Bonding Curve Pool Creation
- **Estimated Gas**: 1,506,359 gas
- **Test Gas Price**: 0.008933858 gwei
- **Test Cost**: 0.000013457 ETH

## Current Base Mainnet Costs (as of October 2025)

Base is an Optimistic Rollup (L2), so gas costs are significantly cheaper than Ethereum mainnet.

### Typical Base Gas Prices:
- **Low**: 0.001 gwei
- **Medium**: 0.01 gwei
- **High**: 0.1 gwei

### Cost Breakdown by Deployment Step:

#### 1. Deploy Temple Token
- **Gas**: ~800,000 (ERC20 deployment)
- **Cost at 0.01 gwei**: ~0.008 ETH (~$20 at $2,500/ETH)

#### 2. Deploy OptimizedTempleHook
- **Gas**: ~1,200,000 (complex hook with CREATE2)
- **Cost at 0.01 gwei**: ~0.012 ETH (~$30 at $2,500/ETH)

#### 3. Create Bonding Curve Pool
- **Gas**: ~1,506,359
  - Pool initialization: ~200,000
  - Permit2 approval: ~100,000
  - 5 position mints: ~1,200,000
- **Cost at 0.01 gwei**: ~0.015 ETH (~$37.50 at $2,500/ETH)

### Total Deployment Costs

| Gas Price | Total ETH | USD (@ $2,500/ETH) |
|-----------|-----------|-------------------|
| 0.001 gwei (very low) | 0.0035 ETH | **$8.75** |
| 0.01 gwei (typical) | 0.035 ETH | **$87.50** |
| 0.1 gwei (high) | 0.35 ETH | **$875** |

## Real-Time Cost Check

To get current Base gas prices, check:
- https://basescan.org/gastracker
- Current Base gas is typically **0.001-0.02 gwei**

## Cost Comparison

### Ethereum Mainnet (for reference)
If deploying on Ethereum L1:
- Gas price: 20-50 gwei (typical)
- **Total cost**: 0.07-0.175 ETH ($175-$437)
- **Much more expensive!**

### Base L2 (Optimistic Rollup)
- Gas price: 0.001-0.01 gwei (typical)
- **Total cost**: 0.0035-0.035 ETH ($8.75-$87.50)
- **~95% cheaper than Ethereum mainnet**

## Additional Costs to Consider

1. **Transaction Confirmation Time**
   - Base: 2-5 seconds per transaction
   - Total deployment: ~15-30 seconds

2. **ETH for Deployment Wallet**
   - Recommended: 0.1 ETH in deployment wallet
   - Covers deployment + buffer for retries

3. **USDC for Testing**
   - None required for deployment!
   - One-sided liquidity = zero USDC upfront
   - Only need USDC if you want to test swaps

## Cost Optimization Tips

1. **Deploy during low-traffic times** (weekends/nights)
2. **Use a gas price oracle** to time deployment
3. **Consider batching operations** if possible
4. **Test thoroughly on Base Sepolia testnet first** (free!)

## Recommended Deployment Plan

### Pre-Deployment (Free):
1. Test on Base Sepolia testnet
2. Verify all contracts compile
3. Prepare wallet with 0.1 ETH

### Mainnet Deployment (~$90):
1. Deploy Temple Token (~$20)
2. Deploy OptimizedHook (~$30)
3. Create Bonding Curve Pool (~$40)
4. **Total: ~$90 at typical gas prices**

### Post-Deployment (Optional):
1. Test swap with USDC (~$0.50)
2. Verify donation mechanism works
3. Monitor pool on Base block explorer

---

**Bottom Line: Expect to spend ~$50-$100 in ETH for full deployment on Base mainnet.**

This is extremely affordable compared to Ethereum mainnet ($200-$500) and ensures your Temple token launches with a proper bonding curve!
