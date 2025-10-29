# Base Mainnet Deployments - v0 Testing

**Chain:** Base Mainnet (8453)
**Deployer:** `0x2226aE701ecf96E27373e896f3ddbe8a9A676A30`
**Date:** October 17, 2025

---

## 🔗 Deployed Contracts

### 1. SimpleTempleHook ✅

**Address:** `0xAc118868b91F149dD4becF6020f4c9B2dAC440c8`
**Basescan:** https://basescan.org/address/0xac118868b91f149dd4becf6020f4c9b2dac440c8

**Configuration:**
- Charity Address: `0xD9082DAa7ce9f68EA2fe36a60BBcc8169A1f6854`
- Charity EIN: `46-0659995`
- Donation Rate: 0.01% (1/100000)
- Donation Manager: `0x2226aE701ecf96E27373e896f3ddbe8a9A676A30` ✅ (Your wallet!)

**Gas Cost:** 0.000022 ETH (~$0.06)

**Hook Permissions:**
- beforeSwap: ✅
- afterSwap: ✅
- beforeSwapReturnDelta: ✅

**Governance Functions:**
- `setCharityAddress(address)` - Update charity recipient
- `setDonationPercentage(uint256)` - Update donation rate (max 3%)
- `setDonationManager(address)` - Transfer manager role

---

### 2. Mock USDC Token ✅

**Address:** `0x60d2711F6d6C9BC2bE61F2e02d9911E568BBDA35`
**Basescan:** https://basescan.org/address/0x60d2711f6d6c9bc2be61f2e02d9911e568bbda35

**Configuration:**
- Name: Mock USDC
- Symbol: mUSDC
- Decimals: 18
- Total Supply: 10,000,000,000 (10 billion)
- Deployer Balance: 10 billion mUSDC

**Gas Cost:** 0.000008 ETH (~$0.02)

**Status:** ✅ Verified on Basescan

---

### 3. Mock Temple Token ✅

**Address:** `0x52c7f7cb6Fa5a48F6Fde92c823F95e74deC21D52`
**Basescan:** https://basescan.org/address/0x52c7f7cb6fa5a48f6fde92c823f95e74dec21d52

**Configuration:**
- Name: Mock Temple
- Symbol: mTEMPLE
- Decimals: 18
- Total Supply: 10,000,000,000 (10 billion)
- Deployer Balance: 10 billion mTEMPLE

**Gas Cost:** 0.000006 ETH (~$0.02)

**Status:** ✅ Verified on Basescan

---

## Environment Variables

```bash
export HOOK_ADDRESS=0xfE09C82b1C12e4787802Cf6025b7AEbf3C5680c8
export MOCK_USDC_ADDRESS=0x60d2711F6d6C9BC2bE61F2e02d9911E568BBDA35
export MOCK_TEMPLE_ADDRESS=0x52c7f7cb6Fa5a48F6Fde92c823F95e74deC21D52
```

---

---

### 4. Bonding Curve Pool ✅

**Pool ID:** mTEMPLE/mUSDC
**Hook:** SimpleTempleHook (0xAc118868b91F149dD4becF6020f4c9B2dAC440c8)

**Configuration:**
- Pool Type: One-sided bonding curve (Temple/USDC)
- Strategy: Clanker "Project" Multi-Position
- Fee: 0.30% (3000)
- Tick Spacing: 200
- Starting Price: ~$0.000027 per mTEMPLE

**Liquidity Positions:**
- Position 1: 1B tokens (10%) - NFT ID 398065
- Position 2: 5B tokens (50%) - NFT ID 398066
- Position 3: 1.5B tokens (15%) - NFT ID 398067
- Position 4: 2B tokens (20%) - NFT ID 398068
- Position 5: 500M tokens (5%) - NFT ID 398069

**Total Liquidity:** 10B mTEMPLE tokens (ZERO mUSDC)

**Gas Cost:** 0.000013 ETH (~$0.03)

---

## Next Steps

- [x] Deploy Mock USDC token
- [x] Deploy Mock Temple token
- [x] Create bonding curve pool (mTEMPLE/mUSDC)
- [ ] Test swaps with donations
