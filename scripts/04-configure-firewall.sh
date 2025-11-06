#!/bin/bash
#
# Script 4: Configure Firewall Rules
# Purpose: Implement security zones and access control
#

set -euo pipefail

echo "=== Configuring Firewall (nftables) ==="

# Clean up existing rules/table for safe re-run
echo "Cleaning up existing firewall (if any)..."
ip netns exec router nft flush ruleset 2>/dev/null || true
ip netns exec router nft delete table ip filter 2>/dev/null || true
echo "  ✓ Cleanup complete"

# Create filter table
echo "Creating filter table..."
ip netns exec router nft add table ip filter

# Create forward chain with default DROP policy
echo "Creating forward chain (default DROP)..."
ip netns exec router nft add chain ip filter forward '{ type filter hook forward priority 0; policy drop; }'

# Allow established/related connections (critical!)
echo "Adding stateful firewall rules..."
ip netns exec router nft add rule ip filter forward ct state established,related accept
echo "  ✓ Allow established/related connections"

# Management zone can access everything
echo "Configuring Management zone rules..."
ip netns exec router nft add rule ip filter forward ip saddr 10.10.10.0/24 accept
ip netns exec router nft add rule ip filter forward ip daddr 10.10.10.0/24 accept
echo "  ✓ Management → ALL"

# DMZ (Web) can reach Internal (App) on port 8080
echo "Configuring DMZ → Internal rules..."
ip netns exec router nft add rule ip filter forward ip saddr 10.10.20.0/24 ip daddr 10.10.30.0/24 tcp dport 8080 ct state new accept
echo "  ✓ Web (DMZ) → App (Internal):8080"

# Internal (App) can reach Database on port 3306
echo "Configuring Internal → Database rules..."
ip netns exec router nft add rule ip filter forward ip saddr 10.10.30.0/24 ip daddr 10.10.40.0/24 tcp dport 3306 ct state new accept
echo "  ✓ App (Internal) → DB (Database):3306"

# Log denied packets (useful for troubleshooting)
echo "Adding logging for dropped packets..."
ip netns exec router nft add rule ip filter forward log prefix "FIREWALL-DROP " level info drop

echo ""
echo "=== Firewall Configuration Complete ==="
echo "  Total rules added: $(ip netns exec router nft list ruleset | wc -l | xargs)"
echo ""
echo "Current ruleset:"
ip netns exec router nft list ruleset

echo ""
echo "=== Testing Firewall Rules ==="
echo ""

# Test function for cleaner output
test_fw() {
    local desc=$1 cmd=$2 expect_pass=$3
    echo -n "$desc: "
    if ip netns exec $cmd > /dev/null 2>&1; then
        [[ $expect_pass == "true" ]] && echo "✓ PASS" || echo "✗ FAIL (should be blocked)"
    else
        [[ $expect_pass == "false" ]] && echo "✓ PASS (correctly blocked)" || echo "✗ FAIL"
    fi
}

# Test 1: Management should reach everything (ICMP allowed)
test_fw "Test 1 - Mgmt → Web" "mgmt ping -c 1 -W 2 10.10.20.10" true
test_fw "Test 2 - Mgmt → App" "mgmt ping -c 1 -W 2 10.10.30.10" true
test_fw "Test 3 - Mgmt → DB" "mgmt ping -c 1 -W 2 10.10.40.10" true

# Test 2: Web should NOT ping App (ICMP blocked, only TCP 8080)
test_fw "Test 4 - Web → App (ping)" "web ping -c 1 -W 2 10.10.30.10" false

# Test 3: Web should NOT reach DB
test_fw "Test 5 - Web → DB (ping)" "web ping -c 1 -W 2 10.10.40.10" false

echo ""
echo "Note: TCP port tests will be performed after services are started"
