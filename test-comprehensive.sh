#!/bin/bash

# Comprehensive Temple Hook Testing
# This script demonstrates the working hook functionality using forge test

set -e

echo "🏛️  Temple Hook Comprehensive Testing"
echo "===================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}🔍 Checking if Anvil is running...${NC}"
if ! curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 >/dev/null; then
    echo -e "${RED}❌ Anvil is not running. Starting it for you...${NC}"
    echo "Starting Anvil in the background..."
    anvil --accounts 10 --balance 1000 --block-time 2 > /dev/null 2>&1 &
    ANVIL_PID=$!
    sleep 3
    echo -e "${GREEN}✅ Anvil started (PID: $ANVIL_PID)${NC}"
else
    echo -e "${GREEN}✅ Anvil is already running${NC}"
    ANVIL_PID=""
fi

echo

# Function to run tests with nice output
run_test_suite() {
    local test_name=$1
    local test_path=$2
    local description=$3
    
    echo -e "${YELLOW}=== $test_name ===${NC}"
    echo -e "${BLUE}$description${NC}"
    echo
    
    if forge test --match-path "$test_path" -v; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
        return 1
    fi
    echo
}

# Test Suite 1: Unit Tests (Hook Configuration & Management)
run_test_suite \
    "Unit Tests" \
    "test/T3MPL3UnitTest.t.sol" \
    "Testing hook configuration, permissions, and management functions"

# Test Suite 2: Simple Integration Tests (Basic Swap with Donation)
run_test_suite \
    "Simple Integration Tests" \
    "test/T3MPL3SimpleTest.t.sol" \
    "Testing basic swap functionality with donation mechanism"

# Detailed test breakdown
echo -e "${YELLOW}=== DETAILED FUNCTIONALITY BREAKDOWN ===${NC}"

echo -e "${BLUE}📋 Running specific functionality tests...${NC}"

echo -e "${YELLOW}1. Hook Configuration Tests${NC}"
forge test --match-path "test/T3MPL3UnitTest.t.sol" --match-test "testHookConfiguration" -v

echo -e "${YELLOW}2. Hook Permissions Tests${NC}"
forge test --match-path "test/T3MPL3UnitTest.t.sol" --match-test "testHookPermissions" -v

echo -e "${YELLOW}3. Donation Management Tests${NC}"
forge test --match-path "test/T3MPL3UnitTest.t.sol" --match-test "testDonationPercentageUpdate" -v
forge test --match-path "test/T3MPL3UnitTest.t.sol" --match-test "testDonationManagerTransfer" -v

echo -e "${YELLOW}4. Security Tests${NC}"
forge test --match-path "test/T3MPL3UnitTest.t.sol" --match-test "testOnlyDonationManagerCanUpdatePercentage" -v
forge test --match-path "test/T3MPL3UnitTest.t.sol" --match-test "testDonationPercentageCap" -v

echo -e "${YELLOW}5. Basic Swap with Donation Test${NC}"
forge test --match-path "test/T3MPL3SimpleTest.t.sol" --match-test "testBasicSwap" -v

echo

# Summary and key findings
echo -e "${YELLOW}=== 📊 TEST RESULTS SUMMARY ===${NC}"

echo -e "${GREEN}✅ WORKING FUNCTIONALITY:${NC}"
echo "   • Hook deployment and configuration ✅"
echo "   • Donation percentage management ✅"
echo "   • Security controls (only manager can change settings) ✅"
echo "   • Basic swap with donation collection ✅"
echo "   • Event emission for donation tracking ✅"
echo "   • AfterSwap hook mechanism ✅"
echo "   • Delta accounting in Uniswap v4 ✅"

echo
echo -e "${BLUE}🔧 TECHNICAL DETAILS:${NC}"
echo "   • Hook uses afterSwap pattern (not beforeSwap) for proper delta accounting"
echo "   • Donations taken from swap output currency"
echo "   • Default donation rate: 0.01% (10/100000)"
echo "   • Maximum donation rate: 1% (1000/100000)"
echo "   • QUBIT charity address: 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720"

echo
echo -e "${YELLOW}💡 KEY LEARNINGS:${NC}"
echo "   • Uniswap v4 hook addresses must encode permissions in the address"
echo "   • AfterSwap hooks are simpler for fee collection than beforeSwap"
echo "   • Delta accounting must be precise to avoid CurrencyNotSettled errors"
echo "   • Hook mining is computationally expensive for deployment scripts"

echo
echo -e "${GREEN}🎉 CONCLUSION: Temple Hook Core Functionality VERIFIED!${NC}"
echo

echo -e "${BLUE}📱 Manual Testing Commands:${NC}"
echo "# Run individual test categories:"
echo "forge test --match-path 'test/T3MPL3UnitTest.t.sol' -v"
echo "forge test --match-path 'test/T3MPL3SimpleTest.t.sol' -v"
echo
echo "# Run specific tests:"
echo "forge test --match-test 'testBasicSwap' -vv"
echo "forge test --match-test 'testHookConfiguration' -v"
echo
echo "# Run all Temple Hook tests:"
echo "forge test --match-path 'test/T3MPL3*.sol' -v"

# Cleanup
if [ -n "$ANVIL_PID" ]; then
    echo
    echo -e "${YELLOW}🧹 Cleaning up...${NC}"
    kill $ANVIL_PID 2>/dev/null || true
    echo -e "${GREEN}✅ Anvil stopped${NC}"
fi

echo
echo -e "${GREEN}🏛️  Temple Hook comprehensive testing complete!${NC}"
echo -e "${BLUE}Your donation mechanism is working correctly! 🎉${NC}"