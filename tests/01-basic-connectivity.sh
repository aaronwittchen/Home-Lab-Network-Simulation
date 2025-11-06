#!/bin/bash
#
# Test 01: Basic Connectivity
#
# This script verifies basic network connectivity between namespaces
# before firewall rules are applied.

set -euo pipefail

echo "=== Basic Connectivity Tests ==="
echo "(Run this before applying firewall rules)"
echo ""

# Test 1: Ping from mgmt to all others
echo "Test 1: Management can reach all hosts"
for ip in 10.10.20.10 10.10.30.10 10.10.40.10; do
    echo -n "  mgmt → $ip: "
    if sudo ip netns exec mgmt ping -c 1 -W 2 $ip >/dev/null 2>&1; then
        echo "✓ OK"
    else
        echo "✗ FAIL"
        exit 1
    fi
done

# Test 2: Ping between non-management hosts
echo -e "\nTest 2: Web can reach App"
if sudo ip netns exec web ping -c 1 -W 2 10.10.30.10 >/dev/null 2>&1; then
    echo "  web → app: ✓ OK"
else
    echo "  web → app: ✗ FAIL"
    exit 1
fi

# Test 3: Check routing tables
echo -e "\nTest 3: Check routing tables"
echo -e "\n=== Management Route Table ==="
sudo ip netns exec mgmt ip route
echo -e "\n=== Router Route Table ==="
sudo ip netns exec router ip route

# Test 4: Traceroute
echo -e "\nTest 4: Traceroute from mgmt to db"
sudo ip netns exec mgmt traceroute -n 10.10.40.10

echo -e "\n=== Basic Connectivity Tests Complete ==="
echo "All tests passed! You can now proceed with firewall configuration."
