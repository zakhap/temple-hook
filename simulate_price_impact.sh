#!/bin/bash

# Uniswap v4 Temple Pool Price Impact Simulation
# Simulates 20 swaps of 0.1 ETH each (2 ETH total) through lopsided Temple pool

echo "=== TEMPLE POOL PRICE IMPACT SIMULATION ==="
echo "Simulating 20 swaps of 0.1 ETH each (2 ETH total)"
echo "Pool Setup: 0.01 ETH + 100,000 Temple tokens"
echo "Fees: 0.30% LP fee + 2% donation fee = 2.30% total"
echo ""

# Initial pool state (in wei and token units)
eth_reserve="10000000000000000"      # 0.01 ETH in wei
temple_reserve="100000000000000000000000"  # 100,000 Temple tokens (18 decimals)

# Calculate initial constant product (k = x * y)
k=$(echo "scale=0; $eth_reserve * $temple_reserve" | bc)

# Calculate initial price (Temple per ETH)
initial_price=$(echo "scale=18; $temple_reserve / $eth_reserve" | bc)

echo "Initial State:"
echo "  ETH Reserve: $(echo "scale=18; $eth_reserve / 1000000000000000000" | bc) ETH"
echo "  Temple Reserve: $(echo "scale=18; $temple_reserve / 1000000000000000000" | bc) Temple"
echo "  Constant Product (k): $k"
echo "  Initial Price: $initial_price Temple per ETH"
echo ""

# Swap parameters
swap_amount="100000000000000000"  # 0.1 ETH in wei
lp_fee_bps="30"                   # 0.30% = 30 basis points
donation_fee_bps="200"            # 2% = 200 basis points
total_fee_bps="230"               # 2.30% total

echo "Swap Parameters:"
echo "  Swap Amount: 0.1 ETH per swap"
echo "  LP Fee: 0.30% (30 bps)"
echo "  Donation Fee: 2% (200 bps)"
echo "  Total Fee: 2.30% (230 bps)"
echo ""

# Track cumulative values
total_eth_swapped="0"
total_temple_received="0"
total_lp_fees="0"
total_donation_fees="0"

echo "Swap Results:"
echo "Swap# | ETH In | LP Fee | Donation Fee | Net ETH | Temple Out | Price | ETH Reserve | Temple Reserve"
echo "------|--------|--------|--------------|---------|------------|-------|-------------|---------------"

# Simulate 20 swaps
for i in {1..20}; do
    # Calculate fees
    lp_fee=$(echo "scale=0; $swap_amount * $lp_fee_bps / 10000" | bc)
    donation_fee=$(echo "scale=0; $swap_amount * $donation_fee_bps / 10000" | bc)
    total_fees=$(echo "scale=0; $lp_fee + $donation_fee" | bc)
    net_eth_input=$(echo "scale=0; $swap_amount - $total_fees" | bc)
    
    # Calculate temple output using constant product formula
    # New ETH reserve = current ETH reserve + net ETH input
    new_eth_reserve=$(echo "scale=0; $eth_reserve + $net_eth_input" | bc)
    
    # New Temple reserve = k / new_eth_reserve
    new_temple_reserve=$(echo "scale=0; $k / $new_eth_reserve" | bc)
    
    # Temple output = current temple reserve - new temple reserve
    temple_output=$(echo "scale=0; $temple_reserve - $new_temple_reserve" | bc)
    
    # Calculate new price (Temple per ETH)
    new_price=$(echo "scale=18; $new_temple_reserve / $new_eth_reserve" | bc)
    
    # Update reserves
    eth_reserve=$new_eth_reserve
    temple_reserve=$new_temple_reserve
    
    # Update cumulative totals
    total_eth_swapped=$(echo "scale=0; $total_eth_swapped + $swap_amount" | bc)
    total_temple_received=$(echo "scale=0; $total_temple_received + $temple_output" | bc)
    total_lp_fees=$(echo "scale=0; $total_lp_fees + $lp_fee" | bc)
    total_donation_fees=$(echo "scale=0; $total_donation_fees + $donation_fee" | bc)
    
    # Format output for display
    eth_in_formatted=$(echo "scale=18; $swap_amount / 1000000000000000000" | bc)
    lp_fee_formatted=$(echo "scale=18; $lp_fee / 1000000000000000000" | bc)
    donation_fee_formatted=$(echo "scale=18; $donation_fee / 1000000000000000000" | bc)
    net_eth_formatted=$(echo "scale=18; $net_eth_input / 1000000000000000000" | bc)
    temple_out_formatted=$(echo "scale=18; $temple_output / 1000000000000000000" | bc)
    eth_reserve_formatted=$(echo "scale=18; $eth_reserve / 1000000000000000000" | bc)
    temple_reserve_formatted=$(echo "scale=18; $temple_reserve / 1000000000000000000" | bc)
    
    printf "%5d | %6.18s | %6.18s | %8.18s | %7.18s | %10.18s | %5.18s | %11.18s | %13.18s\n" \
        $i \
        "$eth_in_formatted" \
        "$lp_fee_formatted" \
        "$donation_fee_formatted" \
        "$net_eth_formatted" \
        "$temple_out_formatted" \
        "$new_price" \
        "$eth_reserve_formatted" \
        "$temple_reserve_formatted"
done

echo ""
echo "=== SIMULATION SUMMARY ==="

# Calculate final metrics
total_eth_formatted=$(echo "scale=18; $total_eth_swapped / 1000000000000000000" | bc)
total_temple_formatted=$(echo "scale=18; $total_temple_received / 1000000000000000000" | bc)
total_lp_fees_formatted=$(echo "scale=18; $total_lp_fees / 1000000000000000000" | bc)
total_donation_fees_formatted=$(echo "scale=18; $total_donation_fees / 1000000000000000000" | bc)

final_price=$(echo "scale=18; $temple_reserve / $eth_reserve" | bc)
price_appreciation=$(echo "scale=18; $final_price / $initial_price" | bc)
average_temple_per_eth=$(echo "scale=18; $total_temple_received / $total_eth_swapped * 1000000000000000000" | bc)

echo "Total ETH Swapped: $total_eth_formatted ETH"
echo "Total Temple Received: $total_temple_formatted Temple"
echo "Total LP Fees Paid: $total_lp_fees_formatted ETH"
echo "Total Donation Fees: $total_donation_fees_formatted ETH"
echo ""
echo "Initial Price: $initial_price Temple per ETH"
echo "Final Price: $final_price Temple per ETH"
echo "Price Appreciation: ${price_appreciation}x"
echo "Average Temple per ETH: $average_temple_per_eth Temple"
echo ""
echo "Pool Final State:"
echo "  ETH Reserve: $(echo "scale=18; $eth_reserve / 1000000000000000000" | bc) ETH"
echo "  Temple Reserve: $(echo "scale=18; $temple_reserve / 1000000000000000000" | bc) Temple"
echo ""
echo "Key Insights:"
echo "  - Lopsided liquidity creates extreme price sensitivity"
echo "  - Each 0.1 ETH swap pushes price higher exponentially"
echo "  - 2% donation fee reduces Temple received by ~2% per swap"
echo "  - Early swaps get significantly more Temple tokens"
echo "  - Price appreciation benefits from concentrated liquidity drain"