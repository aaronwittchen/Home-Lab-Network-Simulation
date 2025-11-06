#!/bin/bash
#
# Teardown Script
# Purpose: Clean up all lab resources
#

set -euo pipefail

echo "=========================================="
echo "Tearing Down Home Lab Network"
echo "=========================================="
echo ""

# Kill services
echo "Stopping services..."
pkill -f "nginx.*homelab" 2>/dev/null && echo "  ✓ Stopped nginx" || true
pkill -f "python3.*8080" 2>/dev/null && echo "  ✓ Stopped app server" || true
pkill -f "python3.*3306" 2>/dev/null && echo "  ✓ Stopped database server" || true

# Delete namespaces (automatically deletes veth pairs)
echo ""
echo "Deleting namespaces..."
for ns in router mgmt web app db; do
    if ip netns list | grep -q "^$ns$"; then
        ip netns del $ns 2>/dev/null && echo "  ✓ Deleted $ns" || echo "  ✗ Failed to delete $ns"
    fi
done

# Clean up temp files
echo ""
echo "Cleaning up temporary files..."
rm -f /tmp/nginx-web-*.log /tmp/nginx-web.pid
rm -f /tmp/app-server.py /tmp/db-server.py
echo "  ✓ Temp files removed"

echo ""
echo "=========================================="
echo "Lab Torn Down Successfully"
echo "=========================================="
echo ""
echo "Verify with: ip netns list"
ip netns list 2>/dev/null || echo "(No namespaces remaining)"
