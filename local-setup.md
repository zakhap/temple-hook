# Temple Hook Local Development Setup

## Prerequisites
- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Node.js/npm (for any frontend integration)

## 1. Start Local Anvil Blockchain

```bash
# Terminal 1: Start Anvil with fixed accounts
anvil --accounts 10 --balance 1000 --block-time 2
```

This creates a local blockchain at `http://localhost:8545` with 10 accounts, each having 1000 ETH.

**Important Addresses:**
- Account 0 (Deployer): `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Account 9 (QUBIT Charity): `0xa0Ee7A142d267C1f36714E4a8F75612F20a79720`

## 2. Deploy Contracts

```bash
# Terminal 2: Deploy all contracts
forge script script/T3MPL3Deployment.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

## 3. Interaction Commands

After deployment, you can interact with the contracts:

### Basic Contract Interactions

```bash
# Check T3MPL3 token balance
cast call <T3MPL3_ADDRESS> "balanceOf(address)" <YOUR_ADDRESS> --rpc-url http://localhost:8545

# Check WETH balance  
cast call <WETH_ADDRESS> "balanceOf(address)" <YOUR_ADDRESS> --rpc-url http://localhost:8545

# Check hook donation percentage
cast call <HOOK_ADDRESS> "getHookDonationPercentage()" --rpc-url http://localhost:8545

# Check QUBIT charity balance
cast call <WETH_ADDRESS> "balanceOf(address)" 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720 --rpc-url http://localhost:8545
```

### Perform Test Swap

```bash
# 1. First approve WETH for swap router
cast send <WETH_ADDRESS> "approve(address,uint256)" <SWAP_ROUTER_ADDRESS> 115792089237316195423570985008687907853269984665640564039457584007913129639935 --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 2. Mint some WETH for testing
cast send <WETH_ADDRESS> "mint(address,uint256)" <YOUR_ADDRESS> 10000000000000000000 --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 3. Perform swap (1 WETH -> T3MPL3, includes donation)
cast send <SWAP_ROUTER_ADDRESS> "swap((address,address,uint24,int24,address),(bool,int256,uint160),(bool,bool),bytes)" "(<CURRENCY0>,<CURRENCY1>,3000,60,<HOOK_ADDRESS>)" "(true,1000000000000000000,<SQRT_PRICE_LIMIT>)" "(false,false)" "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266" --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Update Hook Settings (Only Donation Manager)

```bash
# Update donation percentage (max 1000 = 1%)
cast send <HOOK_ADDRESS> "setDonationPercentage(uint256)" 500 --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Transfer donation manager role
cast send <HOOK_ADDRESS> "setDonationManager(address)" <NEW_MANAGER_ADDRESS> --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## 4. Monitor Events

```bash
# Watch for charitable donation events
cast logs --from-block latest --address <HOOK_ADDRESS> --sig "CharitableDonationTaken(address,bytes32,address,uint256)" --rpc-url http://localhost:8545

# Watch all hook events
cast logs --from-block latest --address <HOOK_ADDRESS> --rpc-url http://localhost:8545
```

## 5. Development Workflow

1. **Start Anvil**: Always start with fresh blockchain for testing
2. **Deploy**: Run deployment script to get contract addresses
3. **Test**: Use cast commands or write integration tests
4. **Reset**: Restart Anvil to reset state when needed

## Troubleshooting

- **"insufficient funds"**: Make sure you have ETH in your account
- **"execution reverted"**: Check approval, balances, and contract addresses
- **Test failures**: Run `forge test -vvv` for detailed error logs
- **Hook issues**: Verify hook address has correct permissions flags

## Contract Addresses

After running the deployment script, note down these addresses:
- PoolManager: `<printed in deployment log>`
- T3MPL3Token: `<printed in deployment log>`  
- SimpleTempleHook: `<printed in deployment log>`
- Mock WETH: `<printed in deployment log>`
- SwapRouter: `<printed in deployment log>`
- LiquidityRouter: `<printed in deployment log>`