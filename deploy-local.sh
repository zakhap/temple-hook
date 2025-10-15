#!/bin/bash
# Local Sepolia Fork Deployment Script
# Run this to deploy all contracts in sequence

set -e

# Configuration
RPC_URL="http://localhost:8545"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"  # Anvil default key

echo "=== DEPLOYING TO LOCAL SEPOLIA FORK ==="
echo "RPC URL: $RPC_URL"

# Step 1: Deploy Temple Token
echo "Step 1: Deploying Temple Token..."
forge script script/DeployTempleToken.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast

# Extract Temple Token address (you'll need to update this after deployment)
# For now, set manually after seeing the deployment output
read -p "Enter Temple Token address: " TEMPLE_TOKEN_ADDRESS
export TEMPLE_TOKEN_ADDRESS

echo "Temple Token deployed at: $TEMPLE_TOKEN_ADDRESS"

# Step 2: Deploy Optimized Hook
echo "Step 2: Deploying Optimized Temple Hook..."
forge script script/DeployOptimizedHook.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast

# Extract Hook address (you'll need to update this after deployment)
read -p "Enter Optimized Hook address: " OPTIMIZED_HOOK_ADDRESS
export OPTIMIZED_HOOK_ADDRESS

echo "Optimized Hook deployed at: $OPTIMIZED_HOOK_ADDRESS"

# Step 3: Create Optimized Pool with Liquidity  
echo "Step 3: Creating Optimized Pool with Liquidity..."
forge script script/CreateOptimizedPool.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast

echo "Pool created with liquidity!"

# Step 4: Test Swap
echo "Step 4: Testing Swap..."
forge script script/SimpleSwap.s.sol \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast

echo "=== DEPLOYMENT COMPLETE ==="
echo "Temple Token: $TEMPLE_TOKEN_ADDRESS"
echo "Optimized Hook: $OPTIMIZED_HOOK_ADDRESS"
echo "Pool created and tested successfully!"