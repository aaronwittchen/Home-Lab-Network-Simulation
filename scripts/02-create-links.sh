#!/bin/bash
#
# Script 2: Create Virtual Ethernet Pairs
# Purpose: Connect namespaces together (like network cables)
#

set -euo pipefail

echo "=== Creating Virtual Ethernet Pairs ==="

# Clean up any existing veth pairs for safe re-run
echo "Cleaning up any existing veth pairs..."
for pair in r-mgmt r-web r-app r-db; do
    ip link del veth-$pair 2>/dev/null || true
    ip link del veth-mgmt-r 2>/dev/null || true  # Peer might linger
    ip link del veth-web-r 2>/dev/null || true
    ip link del veth-app-r 2>/dev/null || true
    ip link del veth-db-r 2>/dev/null || true
    echo "  Cleaned veth-$pair (if existed)"
done

# Function to create and connect veth pair
create_link() {
    local from_ns=$1
    local to_ns=$2
    local from_iface="veth-${from_ns:0:1}-${to_ns}"
    local to_iface="veth-${to_ns}-${from_ns:0:1}"
    
    echo "Creating link: $from_ns <--> $to_ns"
    
    # Create veth pair
    ip link add $from_iface type veth peer name $to_iface
    
    # Move interfaces to respective namespaces
    ip link set $from_iface netns $from_ns
    ip link set $to_iface netns $to_ns
    
    # Bring interfaces up
    ip netns exec $from_ns ip link set $from_iface up
    ip netns exec $to_ns ip link set $to_iface up
    
    echo "  ✓ $from_iface <--> $to_iface"
}

# Create all links
create_link router mgmt
create_link router web
create_link router app
create_link router db

echo ""
echo "=== Links Created Successfully ==="
echo ""
echo "Verify router interfaces:"
ip netns exec router ip link show
