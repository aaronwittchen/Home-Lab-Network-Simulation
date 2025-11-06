#!/bin/bash
#
# Script 1: Create Network Namespaces
# Purpose: Creates isolated network environments
#

set -euo pipefail

echo "=== Creating Network Namespaces ==="

# Clean up any existing namespaces for safe re-run
echo "Cleaning up any existing namespaces..."
for ns in router mgmt web app db; do
    ip netns del $ns 2>/dev/null || true
    echo "  Cleaned $ns (if existed)"
done

# Create namespaces
echo "Creating namespaces..."
ip netns add router
ip netns add mgmt
ip netns add web
ip netns add app
ip netns add db

# Enable loopback interface in each namespace
echo "Enabling loopback interfaces..."
for ns in router mgmt web app db; do
    ip netns exec $ns ip link set lo up
    echo "  ✓ $ns"
done

echo ""
echo "=== Namespaces Created Successfully ==="
echo ""
echo "Verify with: ip netns list"
ip netns list
