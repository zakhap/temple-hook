# Temple Hook Repository Cleanup Guide

## 🎯 Overview
This document provides recommendations for cleaning up the repository before open sourcing your Temple Hook project.

---

## 📊 Current Repository Analysis

### Core Production Contracts (KEEP ✅)

| Contract | Purpose | Status | Notes |
|----------|---------|--------|-------|
| **SimpleTempleHook.sol** | Main hook with charity donations | ✅ Production Ready | Has EIN, clean implementation |
| **OptimizedTempleHook.sol** | Advanced hook with governance | ✅ Production Ready | Has EIN, security features |
| **TempleToken.sol** | ERC20 token for Temple | ✅ Production Ready | Simple, clean |

### Obsolete/Experimental Contracts (REMOVE ❌)

| Contract | Purpose | Recommendation | Reason |
|----------|---------|----------------|--------|
| **Counter.sol** | Template example | ❌ DELETE | v4-template boilerplate, not related to Temple |
| **T3MPL3Hook.sol** | Old version of hook | ❌ DELETE | Replaced by SimpleTempleHook |
| **T3MPL3Token.sol** | Old token version | ❌ DELETE | Replaced by TempleToken |
| **PointsHook.sol** | Unrelated points system | ❌ DELETE | Not part of Temple project |
| **PointsToken.sol** | Points token | ❌ DELETE | Not part of Temple project |
| **ComplexTempleHook.sol** | Experimental all-in-one | ⚠️ ARCHIVE | Interesting but unused |
| **CharityManager.sol** | Standalone charity registry | ⚠️ ARCHIVE | Not used in current design |
| **TempleTokenFactory.sol** | Token factory | ⚠️ ARCHIVE | Not used in current design |

---

## 📜 Production Scripts (KEEP ✅)

### Deployment Scripts
- ✅ **DeployTempleToken.s.sol** - Deploy Temple token
- ✅ **DeployOptimizedHook.s.sol** - Deploy OptimizedTempleHook
- ✅ **CreateBondingCurvePool.s.sol** - Create bonding curve pool
- ✅ **CreateOptimizedPool.s.sol** - Alternative pool creation

### Utility Scripts
- ✅ **base/Constants.sol** - Base mainnet constants
- ✅ **CalculateBondingCurve.s.sol** - Calculate USDC requirements
- ✅ **CheckTickPrices.s.sol** - Verify tick pricing

---

## 🗑️ Obsolete Scripts (REMOVE ❌)

### Template Boilerplate
- ❌ **Anvil.s.sol** - Template deployment script
- ❌ **01a_CreatePoolOnly.s.sol** - Template script
- ❌ **02_AddLiquidity.s.sol** - Template script
- ❌ **03_Swap.s.sol** - Template script

### Experimental/Old Scripts
- ❌ **DeployT3MPL3Token.s.sol** - Old token deployment
- ❌ **T3MPL3Deployment.s.sol** - Old full deployment
- ❌ **SimpleTempleHook.s.sol** - Old hook deployment
- ❌ **SimpleDeployment.s.sol** - Old deployment
- ❌ **DeployHookOnly.s.sol** - Redundant
- ❌ **PointsHookScript.s.sol** - Unrelated points system

### Test/Debug Scripts (Move to examples or delete)
- ⚠️ **SimpleEthSwap.s.sol** - Example swap script
- ⚠️ **SimpleSwap.s.sol** - Example swap script
- ⚠️ **TestSwapHook.s.sol** - Test script
- ⚠️ **TestSwapWithDonation.s.sol** - Test script
- ⚠️ **CreatePoolWithLiquidity.s.sol** - Example script

### Unused Utilities
- ❌ **base/Config.sol** - Not used
- ❌ **mocks/MockER20.s.sol** - Typo in filename, not needed

---

## 🧪 Test Files

### Production Tests (KEEP ✅)
- ✅ **test/temple-hook/OptimizedTempleHookFixed.t.sol** - Main tests
- ✅ **test/temple-hook/integration/SimpleIntegrationTest.t.sol** - Integration tests
- ✅ **test/temple-hook/security/AttackResistanceTest.t.sol** - Security tests
- ✅ **test/temple-hook/governance/GovernanceTest.t.sol** - Governance tests
- ✅ **test/temple-hook/edge-cases/EdgeCaseTest.t.sol** - Edge case tests
- ✅ **test/utils/Fixtures.sol** - Test utilities
- ✅ **test/utils/EasyPosm.sol** - Position manager helper

### Remove These Tests
- ❌ **test/Counter.t.sol** - Template test
- ❌ **test/PointsHook.t.sol** - Unrelated points test
- ❌ **test/custom-accounting/ExampleHook.sol** - Example only
- ❌ **test/custom-accounting/ExampleHook.t.sol** - Example test
- ⚠️ **test/LiveIntegrationTest.t.sol** - Useful for local testing, keep or move

---

## 📚 Documentation Files

### Keep and Update
- ✅ **CLAUDE.md** - Project instructions (update for open source)
- ✅ **BONDING_CURVE_ANALYSIS.md** - Excellent reference
- ✅ **DEPLOYMENT_COSTS.md** - Useful cost info
- ✅ **README.md** - NEEDS COMPLETE REWRITE

### Remove or Archive
- ❌ **HOOK_ACCOUNTING_UPGRADE_PLAN.md** - Implementation notes, not needed for users
- ❌ **local-setup.md** - Outdated
- ❌ **DEPLOYMENT_GUIDE.md** - Outdated
- ❌ **PRICE_DISCOVERY_ANALYSIS.md** - Implementation notes, merge into docs

### Scripts to Remove
- ❌ **deploy-local.sh** - Outdated bash script
- ❌ **simulate_price_impact.sh** - Outdated bash script

---

## 🔧 Configuration Files (KEEP ✅)

- ✅ **foundry.toml** - Build configuration
- ✅ **remappings.txt** - Import paths
- ✅ **.gitignore** - Version control
- ✅ **.gitmodules** - Dependencies
- ✅ **LICENSE** - MIT license
- ⚠️ **.env** - MAKE SURE TO ADD TO .gitignore, remove from git history!

---

## 📁 Directory Structure Recommendations

### Proposed Clean Structure

```
temple-hook/
├── src/
│   ├── SimpleTempleHook.sol          ✅ Main hook (0.01-3% donation)
│   ├── OptimizedTempleHook.sol       ✅ Advanced hook with governance
│   └── TempleToken.sol                ✅ ERC20 token
│
├── script/
│   ├── base/
│   │   └── Constants.sol              ✅ Network constants
│   ├── DeployTempleToken.s.sol        ✅ Token deployment
│   ├── DeployOptimizedHook.s.sol      ✅ Hook deployment
│   ├── CreateBondingCurvePool.s.sol   ✅ Bonding curve setup
│   ├── CreateOptimizedPool.s.sol      ✅ Alternative pool setup
│   ├── CalculateBondingCurve.s.sol    ✅ Utility
│   └── CheckTickPrices.s.sol          ✅ Utility
│
├── test/
│   ├── temple-hook/
│   │   ├── OptimizedTempleHookFixed.t.sol
│   │   ├── integration/
│   │   ├── security/
│   │   ├── governance/
│   │   └── edge-cases/
│   └── utils/
│       ├── Fixtures.sol
│       └── EasyPosm.sol
│
├── docs/                              📁 NEW: Move all markdown here
│   ├── BONDING_CURVE_ANALYSIS.md
│   ├── DEPLOYMENT_COSTS.md
│   ├── DEPLOYMENT_GUIDE.md            📁 NEW: Complete deployment guide
│   └── ARCHITECTURE.md                 📁 NEW: System architecture
│
├── examples/                          📁 NEW: Example scripts
│   └── SimpleSwap.s.sol               (move test scripts here)
│
├── README.md                          ⚠️ NEEDS COMPLETE REWRITE
├── CLAUDE.md                          ✅ Keep
├── foundry.toml                       ✅ Keep
├── remappings.txt                     ✅ Keep
└── LICENSE                            ✅ Keep
```

---

## 🚨 Critical Security Items

### Before Open Sourcing:

1. **Remove .env from git history**
   ```bash
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch .env" \
     --prune-empty --tag-name-filter cat -- --all
   ```

2. **Add .env to .gitignore** (if not already)
   ```bash
   echo ".env" >> .gitignore
   ```

3. **Update hardcoded addresses**
   - ❌ SimpleTempleHook.sol line 58: `0xa0Ee7A142d267C1f36714E4a8F75612F20a79720` (Anvil address)
   - ⚠️ Need real QUBIT charity address for Base mainnet

4. **Remove private keys from scripts**
   - ✅ All scripts use `vm.envAddress()` - GOOD!
   - ⚠️ Documentation examples mention private key - update to use .env

---

## 📝 Documentation TODOs

### New README.md Should Include:
1. Project overview and purpose
2. Features (charitable donations, bonding curve, Base L2)
3. Quick start guide
4. Deployment instructions
5. Testing guide
6. Architecture diagram
7. Security considerations
8. Contributing guidelines
9. License information

### New DEPLOYMENT_GUIDE.md Should Include:
1. Prerequisites
2. Step-by-step deployment on Base
3. Environment variable setup
4. Verification steps
5. Troubleshooting

---

## 🎬 Recommended Action Plan

### Phase 1: Remove Obsolete Code (30 min)
```bash
# Delete obsolete contracts
rm src/Counter.sol src/T3MPL3Hook.sol src/T3MPL3Token.sol
rm src/PointsHook.sol src/PointsToken.sol

# Move to archive/ folder (don't delete yet)
mkdir archive
mv src/ComplexTempleHook.sol archive/
mv src/CharityManager.sol archive/
mv src/TempleTokenFactory.sol archive/

# Delete obsolete scripts
rm script/Anvil.s.sol script/01a_CreatePoolOnly.s.sol
rm script/02_AddLiquidity.s.sol script/03_Swap.s.sol
rm script/DeployT3MPL3Token.s.sol script/T3MPL3Deployment.s.sol
rm script/SimpleTempleHook.s.sol script/SimpleDeployment.s.sol
rm script/DeployHookOnly.s.sol script/PointsHookScript.s.sol
rm script/base/Config.sol
rm -rf script/mocks

# Delete obsolete tests
rm test/Counter.t.sol test/PointsHook.t.sol
rm -rf test/custom-accounting/

# Delete obsolete docs
rm HOOK_ACCOUNTING_UPGRADE_PLAN.md local-setup.md
rm deploy-local.sh simulate_price_impact.sh
```

### Phase 2: Organize Documentation (20 min)
```bash
# Create docs directory
mkdir docs

# Move documentation
mv BONDING_CURVE_ANALYSIS.md docs/
mv DEPLOYMENT_COSTS.md docs/
mv PRICE_DISCOVERY_ANALYSIS.md docs/
mv DEPLOYMENT_GUIDE.md docs/ # Update this file

# Create examples directory
mkdir examples
mv script/SimpleEthSwap.s.sol examples/ (if keeping)
mv script/SimpleSwap.s.sol examples/ (if keeping)
```

### Phase 3: Security Updates (15 min)
- Update QUBIT charity address in both hooks
- Verify .env in .gitignore
- Remove .env from git history if needed
- Review all scripts for hardcoded keys (none found ✅)

### Phase 4: Documentation Rewrite (60 min)
- Write new README.md
- Update DEPLOYMENT_GUIDE.md
- Create ARCHITECTURE.md
- Update CLAUDE.md for contributors

### Phase 5: Final Testing (30 min)
```bash
# Rebuild everything
forge clean
forge build

# Run all tests
forge test

# Verify no broken imports
forge build --force
```

---

## 📊 Summary Statistics

### Files to Delete: 25+
- Contracts: 6
- Scripts: 14+
- Tests: 4
- Docs: 5

### Files to Keep: 15
- Contracts: 3 core
- Scripts: 7 production
- Tests: 5+ suites
- Docs: Need updating

### Estimated Cleanup Time: **2.5 hours**

---

## ✅ Post-Cleanup Checklist

- [ ] All obsolete files removed
- [ ] Documentation organized in `docs/` folder
- [ ] README.md completely rewritten
- [ ] DEPLOYMENT_GUIDE.md updated
- [ ] .env removed from git history
- [ ] QUBIT charity address updated
- [ ] All tests passing
- [ ] `forge build` succeeds
- [ ] No broken imports
- [ ] LICENSE file present
- [ ] Contributing guidelines added
- [ ] GitHub repo description updated
- [ ] GitHub topics added (uniswap, defi, charity, etc.)

---

**Ready to start? Let me know which phase you'd like to begin with!**
