# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Temple Hook is a Uniswap v4 hook system that implements charitable donation mechanisms on Ethereum. It collects small donations (0.01%-1%) from swap transactions and routes them to designated charity addresses. Built on the Uniswap v4 template with comprehensive testing and multiple hook implementations.

## Common Commands

### Development Setup
```bash
# Install dependencies
forge install

# Basic testing
forge test

# Comprehensive testing with detailed output
./test-comprehensive.sh

# Local deployment testing (requires anvil)
./test-local.sh
```

### Testing Commands
```bash
# Run all Temple Hook tests
forge test --match-path "test/T3MPL3*.sol" -v

# Run specific test suites
forge test --match-path "test/T3MPL3UnitTest.t.sol" -v          # Unit tests
forge test --match-path "test/T3MPL3SimpleTest.t.sol" -v       # Integration tests
forge test --match-path "test/T3MPL3Test.t.sol" -v             # Full test suite

# Run specific functionality tests
forge test --match-test "testBasicSwap" -vv
forge test --match-test "testHookConfiguration" -v
forge test --match-test "testDonationPercentageUpdate" -v
```

### Local Development (Anvil)
```bash
# Start local blockchain
anvil --accounts 10 --balance 1000 --block-time 2

# Deploy contracts locally
forge script script/SimpleDeployment.s.sol \
    --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast

# Run comprehensive live testing
./test-local.sh

# Run simple integration tests
./test-simple.sh

# Run live integration tests with Foundry
forge test --match-contract LiveIntegrationTest --rpc-url http://localhost:8545 -vv
```

## Core Architecture

### Main Hook Contracts

- **SimpleTempleHook.sol** - Primary hook implementation using `beforeSwap` pattern
  - Configurable donation rate (0.01% to 3%)
  - Routes donations to QUBIT charity (0xa0Ee7A142d267C1f36714E4a8F75612F20a79720)
  - Proper Uniswap v4 delta accounting with BeforeSwapDelta

- **T3MPL3Hook.sol** - Alternative `beforeSwap` implementation with fixed 1% rate

- **ComplexTempleHook.sol** - All-in-one contract with charity registry and token factory

### Supporting Infrastructure

- **CharityManager.sol** - Standalone charity registry system
- **T3MPL3Token.sol** / **TempleToken.sol** - ERC20 token implementations
- **TempleTokenFactory.sol** - Token creation factory

## Key Technical Patterns

### Hook Implementation
- Uses Uniswap v4 permission system with encoded hook addresses
- `afterSwap` pattern preferred for fee collection (simpler delta accounting)
- Donation taken from swap output currency
- Events emitted for all donations: `CharitableDonationTaken`

### Security Controls
- Role-based access: donation manager can modify settings
- Donation percentage capped at 1% (1000/100000)
- Input validation on all configuration changes

### Testing Strategy
- **Unit Tests**: Hook configuration, permissions, management functions
- **Integration Tests**: Full swap workflows with donation verification
- **Security Tests**: Access control and permission validation
- **Local Deployment Tests**: End-to-end functionality on anvil

## Configuration

### Foundry Settings
- Solidity version: 0.8.26
- EVM version: Cancun
- FFI enabled for hook address mining
- File system permissions for snapshot testing

### Default Values
- Default donation rate: 0.01% (10/100000)
- Maximum donation rate: 3% (3000/100000)
- QUBIT charity address: 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720

## Important Development Notes

### Hook Deployment
- Hook addresses must be mined to encode permissions correctly
- Use CREATE2 Proxy (0x4e59b44847b379578588920cA78FbF26c0B4956C) for deployment scripts
- Address mining is computationally expensive - consider pre-computed addresses

### Delta Accounting
- Critical: Must handle Uniswap v4 currency deltas precisely
- `afterSwap` pattern simpler than `beforeSwap` for fee collection
- Avoid `CurrencyNotSettled` errors through proper balance management

### Testing Workflow
- Always run comprehensive test suite before committing changes
- Use provided test scripts for consistent testing environment
- Verify donation mechanism with balance checks and event monitoring
- Test security controls to ensure only authorized access

## Dependencies

Key dependencies managed via git submodules:
- `v4-core` - Uniswap v4 core contracts
- `v4-periphery` - Uniswap v4 periphery contracts  
- `openzeppelin-contracts` - Standard contract implementations
- `forge-std` - Testing utilities