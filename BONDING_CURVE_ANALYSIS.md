# Bonding Curve Analysis: Temple/USDC

## Overview
- **Total Supply**: 10,000,000,000 Temple (10B tokens)
- **Paired Asset**: USDC (6 decimals)
- **Strategy**: One-sided liquidity (Temple only, zero USDC)
- **Distribution**: 5 concentrated positions following Clanker's "Project" model

## Price Calculation
At tick `-230400` (starting price):
- Raw price in Q96: `7820508539486457102`
- Adjusted for decimals: Temple has 18, USDC has 6 (12 decimal difference)
- **Starting price: ~$0.000098 USDC per Temple**

At tick `-120000` (ending price):
- Raw price in Q96: `487086799803102792261277`
- **Ending price: ~$0.061 USDC per Temple**

## Position Breakdown

### Position 1: "Bootstrap Phase" (10% - 1B Temple)
- **Tick Range**: -230400 to -214000
- **Temple Amount**: 1,000,000,000 tokens
- **Price Range**: $0.000098 → $0.00051 per Temple
- **Market Cap Range**: ~$1K → ~$5K
- **Est. USDC Required**: ~$224 (very cheap early entry!)

### Position 2: "Main Distribution" (50% - 5B Temple)
- **Tick Range**: -214000 to -155000
- **Temple Amount**: 5,000,000,000 tokens
- **Price Range**: $0.00051 → $0.0185 per Temple
- **Market Cap Range**: ~$5K → ~$185K
- **Est. USDC Required**: ~$48,600
- **Cumulative USDC**: ~$48,824

### Position 3: "Overlap Zone" (15% - 1.5B Temple)
- **Tick Range**: -202000 to -155000
- **Temple Amount**: 1,500,000,000 tokens
- **Price Range**: $0.00168 → $0.0185 per Temple
- **Market Cap Range**: ~$17K → ~$185K
- **Est. USDC Required**: ~$26,566
- **Cumulative USDC**: ~$75,390

### Position 4: "Growth Phase" (20% - 2B Temple)
- **Tick Range**: -155000 to -120000
- **Temple Amount**: 2,000,000,000 tokens
- **Price Range**: $0.0185 → $0.061 per Temple
- **Market Cap Range**: ~$185K → ~$610K
- **Est. USDC Required**: ~$2,136,877
- **Cumulative USDC**: ~$2,212,267

### Position 5: "Final Stretch" (5% - 500M Temple)
- **Tick Range**: -141000 to -120000
- **Temple Amount**: 500,000,000 tokens
- **Price Range**: $0.0075 → $0.061 per Temple
- **Market Cap Range**: ~$75K → ~$610K
- **Est. USDC Required**: ~$1,075,748
- **Cumulative USDC**: ~$3,288,014

## Total Bonding Curve Economics

- **Total USDC to exhaust curve**: ~$3,288,014
- **Final market cap**: ~$610,000 (at 10B supply × $0.061/Temple)
- **Average buy-in price**: ~$0.33 per Temple

## Key Insights

1. **Extremely Low Entry**: First 1B tokens can be bought for just ~$224
2. **Steep Curve**: Price increases exponentially through positions
3. **Concentrated Mid-Range**: 65% of supply (Positions 2+3) in the $0.0005-$0.02 range
4. **Final Push Expensive**: Last 25% (Positions 4+5) requires ~$3.2M in USDC
5. **One-Sided Risk**: LP deployer takes no upfront capital risk

## Comparison to Traditional Launch

Traditional launches might require:
- Paired liquidity (e.g., $50K USDC + 5B Temple)
- Fixed price discovery
- Impermanent loss risk for LP

This bonding curve:
- **Zero upfront USDC** required
- Progressive price discovery
- No impermanent loss (one-sided)
- Natural market-driven valuation

---

*Note: These calculations are estimates. Actual USDC requirements may vary slightly due to:*
- *Rounding in fixed-point math*
- *Tick spacing (200) constraints*
- *Slippage and swap fees (0.30%)*
- *Hook donation fees (if enabled)*
