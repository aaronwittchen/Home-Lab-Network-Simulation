#!/bin/bash
#
# Status Check Script
# Purpose: Verify lab configuration and connectivity
#

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Home Lab Network Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check namespaces
echo -e "${YELLOW}Network Namespaces:${NC}"
if ip netns list &> /dev/null; then
    ip netns list | while read ns; do
        echo -e "  ${GREEN}✓${NC} $ns"
    done
else
    echo -e "  ${RED}✗${NC} No namespaces found"
fi
echo ""

# Check router interfaces
echo -e "${YELLOW}Router Interfaces:${NC}"
ip netns exec router ip -br addr 2>/dev/null | grep -v "^lo" || echo -e "  ${RED}✗${NC} Router not found"
echo ""

# Check connectivity
echo -e "${YELLOW}Connectivity Tests:${NC}"

test_ping() {
    local from=$1
    local to=$2
    local ip=$3
    if ip netns exec $from ping -c 1 -W 2 $ip > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $from → $to ($ip)"
    else
        echo -e "  ${RED}✗${NC} $from → $to ($ip)"
    fi
}

test_ping mgmt web 10.10.20.10
test_ping mgmt app 10.10.30.10
test_ping mgmt db 10.10.40.10

echo ""
echo -e "${YELLOW}Firewall Status:${NC}"
if ip netns exec router nft list ruleset | grep -q "chain forward"; then
    echo -e "  ${GREEN}✓${NC} Firewall rules active"
    
    # Test blocked connections
    if ! ip netns exec web ping -c 1 -W 2 10.10.40.10 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Web → DB blocked (correct)"
    else
        echo -e "  ${RED}✗${NC} Web → DB NOT blocked (incorrect)"
    fi
else
    echo -e "  ${RED}✗${NC} No firewall rules found"
fi

echo ""
echo -e "${YELLOW}Running Services:${NC}"

# Check nginx
if pgrep -f "nginx.*homelab" > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Nginx (Web server)"
else
    echo -e "  ${RED}✗${NC} Nginx not running"
fi

# Check app server
if pgrep -f "python3.*8080" > /dev/null; then
    echo -e "  ${GREEN}✓${NC} App server (port 8080)"
else
    echo -e "  ${RED}✗${NC} App server not running"
fi

# Check db server
if pgrep -f "python3.*3306" > /dev/null; then
    echo -e "  ${GREEN}✓${NC} Database server (port 3306)"
else
    echo -e "  ${RED}✗${NC} Database server not running"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
