#!/bin/bash
#
# Test Suite
# Purpose: Automated testing of lab configuration
#

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name=$1
    local test_command=$2
    local expected_result=${3:-0}  # 0 for should pass, 1 for should fail
    
    echo -n "Testing: $test_name ... "
    
    if eval "$test_command" > /dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    if [ $result -eq $expected_result ]; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
    fi
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Running Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Namespace tests
echo -e "${YELLOW}Namespace Tests:${NC}"
run_test "Router namespace exists" "ip netns list | grep -q '^router'"
run_test "Mgmt namespace exists" "ip netns list | grep -q '^mgmt'"
run_test "Web namespace exists" "ip netns list | grep -q '^web'"
run_test "App namespace exists" "ip netns list | grep -q '^app'"
run_test "DB namespace exists" "ip netns list | grep -q '^db'"
echo ""

# Interface tests
echo -e "${YELLOW}Interface Tests:${NC}"
run_test "Router has mgmt interface" "ip netns exec router ip link show veth-r-mgmt"
run_test "Router has web interface" "ip netns exec router ip link show veth-r-web"
run_test "Router has app interface" "ip netns exec router ip link show veth-r-app"
run_test "Router has db interface" "ip netns exec router ip link show veth-r-db"
echo ""

# IP configuration tests
echo -e "${YELLOW}IP Configuration Tests:${NC}"
run_test "Mgmt has correct IP" "ip netns exec mgmt ip addr show veth-mgmt-r | grep -q '10.10.10.10/24'"
run_test "Web has correct IP" "ip netns exec web ip addr show veth-web-r | grep -q '10.10.20.10/24'"
run_test "App has correct IP" "ip netns exec app ip addr show veth-app-r | grep -q '10.10.30.10/24'"
run_test "DB has correct IP" "ip netns exec db ip addr show veth-db-r | grep -q '10.10.40.10/24'"
run_test "Router mgmt IP" "ip netns exec router ip addr show veth-r-mgmt | grep -q '10.10.10.1/24'"
echo ""

# Routing tests
echo -e "${YELLOW}Routing Tests:${NC}"
run_test "Mgmt default route" "ip netns exec mgmt ip route | grep -q 'default via 10.10.10.1'"
run_test "Web default route" "ip netns exec web ip route | grep -q 'default via 10.10.20.1'"
run_test "App default route" "ip netns exec app ip route | grep -q 'default via 10.10.30.1'"
run_test "DB default route" "ip netns exec db ip route | grep -q 'default via 10.10.40.1'"
echo ""

# Connectivity tests (allowed paths)
echo -e "${YELLOW}Allowed Connectivity Tests:${NC}"
run_test "Mgmt → Web ping" "ip netns exec mgmt ping -c 1 -W 2 10.10.20.10"
run_test "Mgmt → App ping" "ip netns exec mgmt ping -c 1 -W 2 10.10.30.10"
run_test "Mgmt → DB ping" "ip netns exec mgmt ping -c 1 -W 2 10.10.40.10"
run_test "Web → App HTTP" "ip netns exec web curl -s -m 2 10.10.30.10:8080"
run_test "App → DB HTTP" "ip netns exec app curl -s -m 2 10.10.40.10:3306"
echo ""

# Blocked connectivity tests (should fail)
echo -e "${YELLOW}Blocked Connectivity Tests:${NC}"
run_test "Web → DB ping (blocked)" "ip netns exec web ping -c 1 -W 2 10.10.40.10" 1
run_test "App → Web HTTP (blocked)" "ip netns exec app curl -s -m 2 10.10.20.10:80" 1
echo ""

# Firewall tests
echo -e "${YELLOW}Firewall Tests:${NC}"
run_test "Firewall chain exists" "ip netns exec router nft list chain ip filter forward"
run_test "Management allow rule" "ip netns exec router nft list ruleset | grep -q '10.10.10.0/24'"
run_test "DMZ to Internal rule" "ip netns exec router nft list ruleset | grep -q 'dport 8080'"
run_test "Internal to DB rule" "ip netns exec router nft list ruleset | grep -q 'dport 3306'"
echo ""

# Service tests
echo -e "${YELLOW}Service Tests:${NC}"
run_test "Web server listening" "ip netns exec web ss -tlnp | grep -q ':80'"
run_test "App server listening" "ip netns exec app ss -tlnp | grep -q ':8080'"
run_test "DB server listening" "ip netns exec db ss -tlnp | grep -q ':3306'"
run_test "Nginx process running" "pgrep -f 'nginx.*homelab'"
run_test "App Python process running" "pgrep -f 'python3.*8080'"
run_test "DB Python process running" "pgrep -f 'python3.*3306'"
echo ""

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC} | Failed: ${RED}$TESTS_FAILED${NC}"
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! Lab is healthy.${NC}"
else
    echo -e "${RED}Some tests failed. Check logs and fix.${NC}"
fi
echo ""
