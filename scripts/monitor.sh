#!/bin/bash
#
# Network Monitor Script
# Purpose: Real-time monitoring of lab network
#

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to get interface stats
get_interface_stats() {
    local ns=$1
    local iface=$2
    
    # Get RX/TX bytes
    local stats=$(ip netns exec $ns ip -s link show $iface 2>/dev/null | grep -A 1 "RX:" | tail -1)
    echo $stats | awk '{print $1}'  # RX bytes
}

# Function to monitor traffic
monitor_traffic() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Network Traffic Monitor${NC}"
    echo -e "${BLUE}Press Ctrl+C to stop${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${YELLOW}$(date)${NC}"
        echo ""
        
        # Router interfaces
        echo -e "${GREEN}Router Interfaces:${NC}"
        ip netns exec router ip -s -br link show | grep veth
        echo ""
        
        # Active connections
        echo -e "${GREEN}Active Connections:${NC}"
        ip netns exec router ss -tn | grep ESTAB | head -10
        echo ""
        
        # Service status
        echo -e "${GREEN}Services:${NC}"
        pgrep -f "nginx.*homelab" > /dev/null && echo -e "  ${GREEN}✓${NC} Nginx" || echo -e "  ${RED}✗${NC} Nginx"
        pgrep -f "python3.*8080" > /dev/null && echo -e "  ${GREEN}✓${NC} App (8080)" || echo -e "  ${RED}✗${NC} App"
        pgrep -f "python3.*3306" > /dev/null && echo -e "  ${GREEN}✓${NC} DB (3306)" || echo -e "  ${RED}✗${NC} DB"
        
        sleep 2
    done
}

# Function to test all paths
test_all_paths() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Testing All Network Paths${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    declare -A tests=(
        ["mgmt→web"]="mgmt 10.10.20.10"
        ["mgmt→app"]="mgmt 10.10.30.10"
        ["mgmt→db"]="mgmt 10.10.40.10"
        ["web→app"]="web 10.10.30.10"
        ["web→db"]="web 10.10.40.10"
        ["app→db"]="app 10.10.40.10"
    )
    
    for test in "${!tests[@]}"; do
        IFS=' ' read -r ns ip <<< "${tests[$test]}"
        echo -n "Testing $test ... "
        if ip netns exec $ns ping -c 1 -W 2 $ip > /dev/null 2>&1; then
            echo -e "${GREEN}PASS${NC}"
        else
            echo -e "${RED}FAIL${NC}"
        fi
    done
}

# Function to show detailed status
show_detailed_status() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Detailed Network Status${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    for ns in router mgmt web app db; do
        echo -e "${YELLOW}Namespace: $ns${NC}"
        ip netns exec $ns ip addr show | grep "inet " | awk '{print "  "$2" on "$NF}'
        echo ""
    done
    
    echo -e "${YELLOW}Firewall Rules Count:${NC}"
    local rule_count=$(ip netns exec router nft list ruleset | grep -c "accept\|drop")
    echo "  $rule_count rules active"
    echo ""
}

# Main menu
case "${1:-}" in
    traffic)
        monitor_traffic
        ;;
    test)
        test_all_paths
        ;;
    detailed)
        show_detailed_status
        ;;
    *)
        echo "Usage: $0 {traffic|test|detailed}"
        echo ""
        echo "Commands:"
        echo "  traffic  - Monitor live traffic (Ctrl+C to exit)"
        echo "  test     - Test all network paths"
        echo "  detailed - Show detailed status"
        exit 1
        ;;
esac
