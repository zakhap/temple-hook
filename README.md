# Temple Hook 🏛️

**Charitable donation hooks for Uniswap v4 on Base L2**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-red)](https://getfoundry.sh/)

Temple Hook enables automatic charitable donations on every swap transaction in Uniswap v4 pools, directing a small percentage of swap volume to verified 501(c)(3) charities on Base L2.

---

## 🌟 Features

- **Automatic Donations**: Seamlessly collect 0.01%-3% from swap transactions
- **Transparent Tracking**: Every donation emits an event with charity EIN
- **Zero Capital Required**: One-sided bonding curve liquidity
- **Base L2 Optimized**: ~95% cheaper gas than Ethereum mainnet
- **Governance Controls**: Configurable donation rates and emergency pause
- **Battle-Tested**: Comprehensive security and edge case testing

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Contracts](#contracts)
- [Quick Start](#quick-start)
- [Deployment](#deployment)
- [Testing](#testing)
- [Documentation](#documentation)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## 🎯 Overview

Temple Hook implements Uniswap v4's hook system to create pools that automatically donate a portion of swap volume to charity. Built for Base L2, it enables cost-effective charitable giving integrated directly into DeFi trading.

### Key Benefits

1. **For Traders**: Support verified charities with every swap
2. **For Projects**: Launch tokens with built-in charitable giving
3. **For Charities**: Receive transparent, on-chain donations with EIN tracking
4. **For Base**: Showcase L2 efficiency for social good

### Supported Charity

- **QUBIT** (EIN: 46-0659995)
- Verified 501(c)(3) organization
- On-chain verification via emitted EIN in every donation event

---

## 🏗️ Architecture

### Hook System

Temple Hook uses Uniswap v4's `beforeSwap` and `afterSwap` hooks to:

1. **Calculate donation** based on swap amount and configured rate
2. **Credit hook** using PoolManager's mint/burn/take accounting
3. **Transfer to charity** via `poolManager.take()`
4. **Emit event** with user, amount, and charity EIN

### Delta Accounting

Properly implements Uniswap v4's delta system:
- `beforeSwap`: Returns `BeforeSwapDelta` indicating donation amount
- Pool Manager charges user for donation automatically
- `afterSwap`: Transfers collected donation to charity

### Bonding Curve

Clanker-inspired multi-position bonding curve:
- **One-sided liquidity**: Zero upfront capital (only Temple tokens)
- **5 concentrated positions**: Progressive price discovery
- **$0.000027 → $0.061**: Starting to ending price range
- **10B token supply**: Distributed across positions

---

## 📦 Contracts

### Core Contracts

| Contract | Purpose | Features |
|----------|---------|----------|
| **SimpleTempleHook** | Main charitable hook | • 0.01-3% donation rate<br>• Configurable by manager<br>• Clean implementation |
| **OptimizedTempleHook** | Advanced hook | • Per-pool configuration<br>• Governance timelock<br>• Emergency pause<br>• Gas optimized |
| **TempleToken** | ERC20 token | • Standard implementation<br>• 10B supply<br>• 18 decimals |

### Contract Addresses (Base Mainnet)

```
Coming soon - not yet deployed
```

---

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/temple-hook.git
cd temple-hook

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Local Testing

```bash
# Start local Base fork
anvil --fork-url https://mainnet.base.org

# In another terminal, deploy locally
forge script script/DeployTempleToken.s.sol \
    --rpc-url http://localhost:8545 \
    --broadcast \
    --private-key <YOUR_PRIVATE_KEY>
```

---

## 🛠️ Deployment

### Environment Setup

Create a `.env` file:

```bash
# Base RPC
BASE_RPC_URL=https://mainnet.base.org

# Deployment wallet
PRIVATE_KEY=your_private_key_here

# Contract addresses (after deployment)
TEMPLE_TOKEN_ADDRESS=
OPTIMIZED_HOOK_ADDRESS=
```

### Deployment Scripts

```bash
# 1. Deploy Temple Token
forge script script/DeployTempleToken.s.sol \
    --rpc-url $BASE_RPC_URL \
    --broadcast \
    --verify

# 2. Deploy Optimized Hook
TEMPLE_TOKEN_ADDRESS=<from_step_1> \
forge script script/DeployOptimizedHook.s.sol \
    --rpc-url $BASE_RPC_URL \
    --broadcast \
    --verify

# 3. Create Bonding Curve Pool
TEMPLE_TOKEN_ADDRESS=<from_step_1> \
OPTIMIZED_HOOK_ADDRESS=<from_step_2> \
forge script script/CreateBondingCurvePool.s.sol \
    --rpc-url $BASE_RPC_URL \
    --broadcast
```

### Cost Estimate

Deployment on Base mainnet costs approximately **$50-$100 USD**:
- Temple Token: ~$20
- Optimized Hook: ~$30
- Bonding Curve Pool: ~$40

See [DEPLOYMENT_COSTS.md](DEPLOYMENT_COSTS.md) for detailed breakdown.

---

## 🧪 Testing

### Run All Tests

```bash
forge test
```

### Test Suites

| Suite | Command | Purpose |
|-------|---------|---------|
| **Unit Tests** | `forge test --match-contract OptimizedTempleHookFixed` | Core functionality |
| **Integration** | `forge test --match-path "test/temple-hook/integration/*"` | End-to-end flows |
| **Security** | `forge test --match-path "test/temple-hook/security/*"` | Attack resistance |
| **Governance** | `forge test --match-path "test/temple-hook/governance/*"` | Admin functions |
| **Edge Cases** | `forge test --match-path "test/temple-hook/edge-cases/*"` | Boundary conditions |

### Test Coverage

```bash
forge coverage
```

### Gas Profiling

```bash
forge test --gas-report
```

---

## 📚 Documentation

### Core Documents

- **[BONDING_CURVE_ANALYSIS.md](BONDING_CURVE_ANALYSIS.md)** - Detailed bonding curve economics
- **[DEPLOYMENT_COSTS.md](DEPLOYMENT_COSTS.md)** - Gas costs and estimates
- **[CLAUDE.md](CLAUDE.md)** - Project instructions for AI assistants
- **[CLEANUP_SUMMARY.md](CLEANUP_SUMMARY.md)** - Repository cleanup history

### Key Concepts

#### Donation Mechanism

```solidity
// User swaps 100 USDC for Temple
// Hook calculates: 100 * 0.0001 (0.01%) = 0.01 USDC donation
// User pays: 100 USDC + fees
// Charity receives: 0.01 USDC
// User receives: Temple tokens (minus 0.01 USDC worth)
```

#### Event Tracking

Every donation emits:
```solidity
event CharitableDonationTaken(
    address indexed user,
    PoolId indexed poolId,
    Currency indexed donationCurrency,
    uint256 donationAmount,
    string charityEIN  // "46-0659995"
);
```

#### Bonding Curve Economics

Starting with 10B Temple tokens distributed across 5 positions:

| Position | Tokens | USDC Required | Price Range |
|----------|--------|---------------|-------------|
| 1 | 1B (10%) | ~$224 | $0.000027 → $0.00051 |
| 2 | 5B (50%) | ~$48,600 | $0.00051 → $0.0185 |
| 3 | 1.5B (15%) | ~$26,566 | $0.00168 → $0.0185 |
| 4 | 2B (20%) | ~$2.1M | $0.0185 → $0.061 |
| 5 | 500M (5%) | ~$1.1M | $0.0075 → $0.061 |

Total: ~$3.3M USDC to exhaust all positions

---

## 🔒 Security

### Audits

⚠️ **Not yet audited** - Use at your own risk in production

### Security Features

- ✅ Reentrancy protection
- ✅ Access control on admin functions
- ✅ Governance timelock (1 day)
- ✅ Emergency pause mechanism
- ✅ Rate limiting on config changes
- ✅ Donation caps (max 1-3%)
- ✅ Input validation
- ✅ Comprehensive test coverage

### Known Limitations

1. **Charity Address**: Immutable after deployment
2. **Pool Specific**: Hook applies to all pools using it
3. **Base Only**: Designed for Base L2 (can adapt for other chains)

### Reporting Issues

Found a security vulnerability? Please email: [your-security-email]

---

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

### Development Setup

```bash
# Fork the repository
git clone https://github.com/yourusername/temple-hook.git
cd temple-hook

# Create a branch
git checkout -b feature/your-feature

# Make changes and test
forge test

# Commit and push
git add .
git commit -m "feat: your feature description"
git push origin feature/your-feature
```

### Pull Request Process

1. Ensure all tests pass (`forge test`)
2. Update documentation as needed
3. Add tests for new features
4. Follow existing code style
5. Reference any related issues

### Code Style

- Use Solidity 0.8.26
- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Add NatSpec comments for public functions
- Write comprehensive tests

---

## 📖 Resources

### Uniswap v4

- [Uniswap v4 Docs](https://docs.uniswap.org/contracts/v4/overview)
- [v4-core](https://github.com/Uniswap/v4-core)
- [v4-periphery](https://github.com/Uniswap/v4-periphery)
- [v4-by-example](https://v4-by-example.org)

### Base L2

- [Base Docs](https://docs.base.org)
- [Base Block Explorer](https://basescan.org)
- [Base Bridge](https://bridge.base.org)

### Related Projects

- [Clanker SDK](https://github.com/mykcryptodev/clanker-sdk) - Bonding curve inspiration

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Uniswap Foundation** - v4 hooks system
- **Base Team** - L2 infrastructure
- **QUBIT** - Charitable partnership
- **Clanker** - Bonding curve design inspiration

---

## 📞 Contact

- **GitHub Issues**: [Report bugs or request features](https://github.com/yourusername/temple-hook/issues)
- **Twitter**: [@yourhandle]
- **Discord**: [Your Discord server]

---

**Built with ❤️ for charitable giving in DeFi**

*Temple Hook - Making every swap count for charity*
