#!/bin/bash
#
# Script 3: Configure IP Addresses
# Purpose: Assign IPs and default routes
#

set -euo pipefail

echo "=== Configuring IP Addresses ==="

# Clean up existing configs for safe re-run
echo "Cleaning up existing IPs and routes..."
for ns in router mgmt web app db; do
    # Flush IPs on relevant interfaces
    ip netns exec $ns ip addr flush dev lo 2>/dev/null || true  # Just in case
    case $ns in
        router)
            for iface in veth-r-mgmt veth-r-web veth-r-app veth-r-db; do
                ip netns exec $ns ip addr flush dev $iface 2>/dev/null || true
            done
            ip netns exec $ns ip route flush table main 2>/dev/null || true
            ;;
        mgmt) iface="veth-mgmt-r"; ip netns exec $ns ip addr flush dev $iface 2>/dev/null || true ;;
        web)  iface="veth-web-r";  ip netns exec $ns ip addr flush dev $iface 2>/dev/null || true ;;
        app)  iface="veth-app-r";  ip netns exec $ns ip addr flush dev $iface 2>/dev/null || true ;;
        db)   iface="veth-db-r";   ip netns exec $ns ip addr flush dev $iface 2>/dev/null || true ;;
    esac
    ip netns exec $ns ip route flush table main 2>/dev/null || true  # Clear routes
done
echo "  ✓ Cleanup complete"

# Router interfaces (gateways)
echo "Configuring router interfaces..."
ip netns exec router ip addr add 10.10.10.1/24 dev veth-r-mgmt
ip netns exec router ip addr add 10.10.20.1/24 dev veth-r-web
ip netns exec router ip addr add 10.10.30.1/24 dev veth-r-app
ip netns exec router ip addr add 10.10.40.1/24 dev veth-r-db
echo "  ✓ Router IPs configured"

# Host interfaces
echo "Configuring host interfaces..."
ip netns exec mgmt ip addr add 10.10.10.10/24 dev veth-mgmt-r
ip netns exec web ip addr add 10.10.20.10/24 dev veth-web-r
ip netns exec app ip addr add 10.10.30.10/24 dev veth-app-r
ip netns exec db ip addr add 10.10.40.10/24 dev veth-db-r
echo "  ✓ Host IPs configured"

# Default routes (point to router)
echo "Configuring default routes..."
ip netns exec mgmt ip route add default via 10.10.10.1
ip netns exec web ip route add default via 10.10.20.1
ip netns exec app ip route add default via 10.10.30.1
ip netns exec db ip route add default via 10.10.40.1
echo "  ✓ Default routes configured"

# Enable forwarding in router
echo "Enabling IP forwarding in router..."
ip netns exec router sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "  ✓ IP forwarding enabled"

echo ""
echo "=== IP Configuration Complete ==="
echo ""
echo "IP Assignments:"
echo "  Management: 10.10.10.10 (Gateway: 10.10.10.1)"
echo "  Web (DMZ):  10.10.20.10 (Gateway: 10.10.20.1)"
echo "  App:        10.10.30.10 (Gateway: 10.10.30.1)"
echo "  Database:   10.10.40.10 (Gateway: 10.10.40.1)"
echo ""
echo "Testing connectivity..."
test_ping() {
    local from=$1 to=$2 ip=$3
    echo -n "  $from → $to:  "
    ip netns exec $from ping -c 1 -W 2 $ip > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"
}
test_ping mgmt web 10.10.20.10
test_ping web app 10.10.30.10
test_ping app db 10.10.40.10
# Extra: Router to a host
test_ping router mgmt 10.10.10.10
