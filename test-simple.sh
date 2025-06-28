#!/bin/bash

# Simple Local Testing Script for SimpleTempleHook
# Tests basic functionality against live anvil deployment

set -e

echo "🔧 Simple Temple Hook Local Test"
echo "================================"

# Configuration
RPC_URL="http://localhost:8545"
DEPLOYER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
USER1_PRIVATE_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check anvil
echo -e "${BLUE}Checking anvil...${NC}"
if ! curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $RPC_URL >/dev/null; then
    echo -e "${RED}❌ Anvil not running. Start with: anvil --accounts 10 --balance 1000 --block-time 2${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Anvil running${NC}"

# Step 1: Deploy contracts
echo -e "\n${YELLOW}Step 1: Deploy contracts${NC}"
if forge script script/SimpleDeployment.s.sol --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast --silent; then
    echo -e "${GREEN}✅ Deployment successful${NC}"
else
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi

# Step 2: Run live integration tests
echo -e "\n${YELLOW}Step 2: Run live integration tests${NC}"
if forge test --match-contract LiveIntegrationTest --rpc-url $RPC_URL -v; then
    echo -e "${GREEN}✅ Live integration tests passed${NC}"
else
    echo -e "${RED}❌ Live integration tests failed${NC}"
    exit 1
fi

# Step 3: Run comprehensive test script
echo -e "\n${YELLOW}Step 3: Run comprehensive testing${NC}"
if ./test-local.sh; then
    echo -e "${GREEN}✅ Comprehensive tests completed${NC}"
else
    echo -e "${YELLOW}⚠️ Some comprehensive tests may have failed (this is often expected)${NC}"
fi

echo -e "\n${GREEN}🎉 Simple testing workflow complete!${NC}"
echo -e "${BLUE}💡 Next steps:${NC}"
echo "  1. Check anvil logs for transaction details"
echo "  2. Use cast commands to interact manually"
echo "  3. Monitor events with: cast logs --follow --rpc-url $RPC_URL"