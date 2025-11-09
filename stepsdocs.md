# Home Lab Network Simulation
Install all necessary packages on the vm
red hat / rocky linux

```bash
# 1. Update system first
sudo dnf update -y

# 2. Install networking tools
sudo dnf install -y \
    iproute \
    iptables-services \
    nftables \
    bridge-utils \
    net-tools

# 3. Install monitoring/debugging tools
sudo dnf install -y \
    tcpdump \
    wireshark-cli \
    mtr \
    traceroute \
    bind-utils \
    nmap

# 4. Install services (we'll use later)
sudo dnf install -y \
    nginx \
    python3 \
    frr

# 5. Install utilities
sudo dnf install -y \
    git \
    vim \
    tmux \
    tree

# 6. Verify installations
which ip nft tcpdump nginx python3
```

**Checkpoint:** All commands should return paths (e.g., `/usr/sbin/ip`)

---

### Session 1.3: Enable IP Forwarding (5 minutes)

**Goal:** Allow routing between namespaces

```bash
# 1. Enable temporarily (for testing)
sudo sysctl -w net.ipv4.ip_forward=1

# 2. Make permanent (survives reboot)
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-ip-forward.conf

# 3. Apply configuration
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf

# 4. Verify
sysctl net.ipv4.ip_forward
# Should show: net.ipv4.ip_forward = 1
```

**Checkpoint:** Command output shows `= 1`

---

### Session 1.4: Create Network Diagram (30 minutes)

**Goal:** Document your design before building

```bash
# Create documentation file
cat > docs/network-design.md << 'EOF'
# Network Design Documentation

## Topology

```
                    Router (10.10.x.1)
                           |
        +------------------+------------------+
        |                  |                  |
    VLAN 10            VLAN 20            VLAN 30         VLAN 40
  Management            DMZ              Internal        Database
  10.10.10.0/24     10.10.20.0/24     10.10.30.0/24   10.10.40.0/24
        |                  |                  |              |
   Jump Host          Web Server         App Server     DB Server
   .10                    .10                .10            .10
```

## IP Allocation Table

| Host         | Interface    | IP Address    | Gateway     | Purpose           |
|--------------|--------------|---------------|-------------|-------------------|
| router       | veth-r-mgmt  | 10.10.10.1/24 | N/A         | Management GW     |
| router       | veth-r-web   | 10.10.20.1/24 | N/A         | DMZ GW            |
| router       | veth-r-app   | 10.10.30.1/24 | N/A         | Internal GW       |
| router       | veth-r-db    | 10.10.40.1/24 | N/A         | Database GW       |
| mgmt         | veth-mgmt-r  | 10.10.10.10/24| 10.10.10.1  | Jump/Admin host   |
| web          | veth-web-r   | 10.10.20.10/24| 10.10.20.1  | Nginx web server  |
| app          | veth-app-r   | 10.10.30.10/24| 10.10.30.1  | App backend       |
| db           | veth-db-r    | 10.10.40.10/24| 10.10.40.1  | Database server   |

## Security Zones

### Management Zone (VLAN 10)
- **Trust Level:** Highest
- **Access:** Can reach all other zones
- **Incoming:** SSH only from specific IPs

### DMZ Zone (VLAN 20)
- **Trust Level:** Low (public-facing)
- **Access:** Can reach Internal zone on port 8080
- **Incoming:** HTTP/HTTPS from anywhere

### Internal Zone (VLAN 30)
- **Trust Level:** Medium
- **Access:** Can reach Database zone on port 3306
- **Incoming:** Only from DMZ on port 8080

### Database Zone (VLAN 40)
- **Trust Level:** Highest (most protected)
- **Access:** No outbound access
- **Incoming:** Only from Internal on port 3306

## Firewall Rules Summary

```
ACCEPT: mgmt (10.10.10.0/24) → ALL
ACCEPT: web (10.10.20.0/24) → app (10.10.30.0/24):8080
ACCEPT: app (10.10.30.0/24) → db (10.10.40.0/24):3306
DROP: Everything else
```
EOF

# Commit documentation
git add docs/
git commit -m "Add network design documentation"
```

**Checkpoint:** Review `docs/network-design.md` - make sure you understand the design

---

### Session 1.5: Create Script 1 - Namespaces (15 minutes)

**Goal:** Create namespaces (virtual network devices)

```bash
# Create the script
cat > scripts/01-create-namespaces.sh << 'EOF'
#!/bin/bash
#
# Script 1: Create Network Namespaces
# Purpose: Creates isolated network environments
#

set -euo pipefail

echo "=== Creating Network Namespaces ==="

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
EOF

sync-project.sh
ubuntu wsl
cd /mnt/c/Users/theon/Desktop/Home\ Lab\ Network\ Simulation/
chmod +x scripts/sync-project.sh
chmod +x scripts/01-create-namespaces.sh
./scripts/sync-project.sh dry-run
./scripts/sync-project.sh

in vm
cd ~/homelab/
sudo ./scripts/01-create-namespaces.sh

# Make executable
chmod +x scripts/01-create-namespaces.sh

# Test it
sudo ./scripts/01-create-namespaces.sh
```

**Expected Output:**
```
=== Creating Network Namespaces ===
Creating namespaces...
Enabling loopback interfaces...
  ✓ router
  ✓ mgmt
  ✓ web
  ✓ app
  ✓ db

=== Namespaces Created Successfully ===

Verify with: ip netns list
db
app
web
mgmt
router
```

**Checkpoint:** Run `ip netns list` - should see 5 namespaces

**Test loopback:**
```bash
# Test that loopback works in a namespace
sudo ip netns exec mgmt ping -c 2 127.0.0.1
# Should see successful pings
```

---

### Session 1.6: Create Script 2 - Virtual Links (20 minutes)

**Goal:** Connect namespaces with virtual ethernet cables

```bash
cat > scripts/02-create-links.sh << 'EOF'
#!/bin/bash
#
# Script 2: Create Virtual Ethernet Pairs
# Purpose: Connect namespaces together (like network cables)
#

set -euo pipefail

echo "=== Creating Virtual Ethernet Pairs ==="

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
EOF

chmod +x scripts/02-create-links.sh

# Test it
sudo ./scripts/02-create-links.sh
```

**Expected Output:**
```
=== Creating Virtual Ethernet Pairs ===
Creating link: router <--> mgmt
  ✓ veth-r-mgmt <--> veth-mgmt-r
Creating link: router <--> web
  ✓ veth-r-web <--> veth-web-r
Creating link: router <--> app
  ✓ veth-r-app <--> veth-app-r
Creating link: router <--> db
  ✓ veth-r-db <--> veth-db-r

=== Links Created Successfully ===
```

**Checkpoint:** Verify links exist
```bash
# Should see 4 veth interfaces in router
sudo ip netns exec router ip link show | grep veth
```

---

### Session 1.7: Create Script 3 - IP Addresses (20 minutes)

**Goal:** Assign IP addresses to all interfaces

```bash
cat > scripts/03-configure-ips.sh << 'EOF'
#!/bin/bash
#
# Script 3: Configure IP Addresses
# Purpose: Assign IPs and default routes
#

set -euo pipefail

echo "=== Configuring IP Addresses ==="

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
echo -n "  mgmt → web:  "
ip netns exec mgmt ping -c 1 -W 2 10.10.20.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"
echo -n "  web → app:   "
ip netns exec web ping -c 1 -W 2 10.10.30.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"
echo -n "  app → db:    "
ip netns exec app ping -c 1 -W 2 10.10.40.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"
EOF

chmod +x scripts/03-configure-ips.sh

# Test it
sudo ./scripts/03-configure-ips.sh
```

**Expected Output:**
```
=== Configuring IP Addresses ===
Configuring router interfaces...
  ✓ Router IPs configured
Configuring host interfaces...
  ✓ Host IPs configured
Configuring default routes...
  ✓ Default routes configured
Enabling IP forwarding in router...
  ✓ IP forwarding enabled

=== IP Configuration Complete ===

IP Assignments:
  Management: 10.10.10.10 (Gateway: 10.10.10.1)
  Web (DMZ):  10.10.20.10 (Gateway: 10.10.20.1)
  App:        10.10.30.10 (Gateway: 10.10.30.1)
  Database:   10.10.40.10 (Gateway: 10.10.40.1)

Testing connectivity...
  mgmt → web:  ✓ OK
  web → app:   ✓ OK
  app → db:    ✓ OK
```

**Checkpoint:** All pings should succeed (✓ OK)

**Manual verification:**
```bash
# Check IP on mgmt namespace
sudo ip netns exec mgmt ip addr show veth-mgmt-r

# Should see: inet 10.10.10.10/24

# Check routes
sudo ip netns exec mgmt ip route
# Should see: default via 10.10.10.1
```

---

### Session 1.8: Test Basic Connectivity (15 minutes)

**Goal:** Verify everything works before adding firewall

```bash
# Test 1: Ping from mgmt to all others
echo "Test 1: Management can reach all hosts"
sudo ip netns exec mgmt ping -c 2 10.10.20.10  # Web
sudo ip netns exec mgmt ping -c 2 10.10.30.10  # App
sudo ip netns exec mgmt ping -c 2 10.10.40.10  # DB

# Test 2: Ping between non-management hosts (should work now, will be blocked later)
echo "Test 2: Web can reach App"
sudo ip netns exec web ping -c 2 10.10.30.10

# Test 3: Check routing table
echo "Test 3: Check routing tables"
echo "=== Management Route Table ==="
sudo ip netns exec mgmt ip route
echo ""
echo "=== Router Route Table ==="
sudo ip netns exec router ip route

# Test 4: Traceroute to see path
echo "Test 4: Traceroute from mgmt to db"
sudo ip netns exec mgmt traceroute -n 10.10.40.10
```

**Expected:** All pings work, traceroute shows one hop (through router)
chmod +x tests/01-basic-connectivity.sh
sudo ./tests/01-basic-connectivity.sh
**Checkpoint:** Save this state before adding firewall
```bash
cd ~/homelab
git add scripts/
git commit -m "Day 1 complete: Basic network connectivity working"
```

---

## 🎉 Day 1 Complete!

**What you've accomplished:**
- ✅ Project structure with git
- ✅ All software installed
- ✅ 5 network namespaces created
- ✅ Virtual links connecting them
- ✅ IP addressing configured
- ✅ Basic routing working
- ✅ Connectivity verified

**Current state:** All hosts can ping each other (no security yet)

---

## Day 2: Security & Services (2-3 hours)

### Session 2.1: Create Script 4 - Firewall Rules (45 minutes)

**Goal:** Implement security zones with nftables

```bash
cat > scripts/04-configure-firewall.sh << 'EOF'
#!/bin/bash
#
# Script 4: Configure Firewall Rules
# Purpose: Implement security zones and access control
#

set -euo pipefail

echo "=== Configuring Firewall (nftables) ==="

# Flush any existing rules
echo "Flushing existing rules..."
ip netns exec router nft flush ruleset

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
ip netns exec router nft add rule ip filter forward log prefix '"[FIREWALL-DROP] "' level info drop

echo ""
echo "=== Firewall Configuration Complete ==="
echo ""
echo "Current ruleset:"
ip netns exec router nft list ruleset

echo ""
echo "=== Testing Firewall Rules ==="
echo ""

# Test 1: Management should reach everything
echo -n "Test 1 - Mgmt → Web:  "
ip netns exec mgmt ping -c 1 -W 2 10.10.20.10 > /dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL"

echo -n "Test 2 - Mgmt → App:  "
ip netns exec mgmt ping -c 1 -W 2 10.10.30.10 > /dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL"

echo -n "Test 3 - Mgmt → DB:   "
ip netns exec mgmt ping -c 1 -W 2 10.10.40.10 > /dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL"

# Test 2: Web should NOT be able to ping App (ICMP blocked, only TCP 8080 allowed)
echo -n "Test 4 - Web → App (ping): "
ip netns exec web ping -c 1 -W 2 10.10.30.10 > /dev/null 2>&1 && echo "✗ FAIL (should be blocked)" || echo "✓ PASS (correctly blocked)"

# Test 3: Web should NOT reach DB at all
echo -n "Test 5 - Web → DB (ping): "
ip netns exec web ping -c 1 -W 2 10.10.40.10 > /dev/null 2>&1 && echo "✗ FAIL (should be blocked)" || echo "✓ PASS (correctly blocked)"

echo ""
echo "Note: TCP port tests will be performed after services are started"
EOF

chmod +x scripts/04-configure-firewall.sh

# Test it
sudo ./scripts/04-configure-firewall.sh
```

**Expected Output:**
```
Test 1 - Mgmt → Web:  ✓ PASS
Test 2 - Mgmt → App:  ✓ PASS
Test 3 - Mgmt → DB:   ✓ PASS
Test 4 - Web → App (ping): ✓ PASS (correctly blocked)
Test 5 - Web → DB (ping): ✓ PASS (correctly blocked)
```

**Checkpoint:** Verify firewall is working
```bash
# This should work (from management)
sudo ip netns exec mgmt ping -c 2 10.10.20.10

# This should FAIL (web can't ping app directly)
sudo ip netns exec web ping -c 2 10.10.30.10
# Should say "Network unreachable" or timeout
```

---

### Session 2.2: Create Script 5 - Start Services (30 minutes)

**Goal:** Run actual services to test firewall with real traffic

```bash
cat > scripts/05-start-services.sh << 'EOF'
#!/bin/bash
#
# Script 5: Start Services
# Purpose: Run web/app/db services in namespaces
#

set -euo pipefail

echo "=== Starting Services ==="

# Kill any existing services
pkill -f "nginx.*homelab" 2>/dev/null || true
pkill -f "python3.*8080" 2>/dev/null || true
pkill -f "python3.*3306" 2>/dev/null || true

# Create nginx config
mkdir -p ~/homelab/configs

cat > ~/homelab/configs/nginx-web.conf << 'NGINX_EOF'
daemon off;
error_log /tmp/nginx-web-error.log info;
pid /tmp/nginx-web.pid;

events {
    worker_connections 1024;
}

http {
    access_log /tmp/nginx-web-access.log;
    
    server {
        listen 10.10.20.10:80;
        
        location / {
            return 200 "Web Server (DMZ)\nVLAN: 20\nIP: 10.10.20.10\n";
            add_header Content-Type text/plain;
        }
        
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
}
NGINX_EOF

# Start web server (nginx in DMZ)
echo "Starting web server (nginx) in DMZ..."
sudo ip netns exec web nginx -c ~/homelab/configs/nginx-web.conf > /dev/null 2>&1 &
sleep 2
echo "  ✓ Web server started on 10.10.20.10:80"

# Start app server (simple Python HTTP server)
echo "Starting app server (Python) in Internal zone..."
cat > /tmp/app-server.py << 'PYTHON_EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler

class AppHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        response = "App Server (Internal)\nVLAN: 30\nIP: 10.10.30.10\n"
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        pass  # Suppress logs

httpd = HTTPServer(('10.10.30.10', 8080), AppHandler)
httpd.serve_forever()
PYTHON_EOF

chmod +x /tmp/app-server.py
sudo ip netns exec app python3 /tmp/app-server.py > /dev/null 2>&1 &
sleep 1
echo "  ✓ App server started on 10.10.30.10:8080"

# Start database server (mock - just another Python server)
echo "Starting database server (mock) in Database zone..."
cat > /tmp/db-server.py << 'PYTHON_EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler

class DBHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        response = "Database Server (Database Zone)\nVLAN: 40\nIP: 10.10.40.10\n"
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        pass

httpd = HTTPServer(('10.10.40.10', 3306), DBHandler)
httpd.serve_forever()
PYTHON_EOF

chmod +x /tmp/db-server.py
sudo ip netns exec db python3 /tmp/db-server.py > /dev/null 2>&1 &
sleep 1
echo "  ✓ Database server started on 10.10.40.10:3306"

echo ""
echo "=== Services Started Successfully ==="
echo ""
echo "Service Endpoints:"
echo "  Web:      http://10.10.20.10:80"
echo "  App:      http://10.10.30.10:8080"
echo "  Database: http://10.10.40.10:3306"
echo ""

echo "=== Testing Service Access (with Firewall) ==="
echo ""

# Test from management (should all work)
echo "From Management namespace:"
echo -n "  → Web:      "
sudo ip netns exec mgmt curl -s -m 2 10.10.20.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"
echo -n "  → App:      "
sudo ip netns exec mgmt curl -s -m 2 10.10.30.10:8080 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"
echo -n "  → Database: "
sudo ip netns exec mgmt curl -s -m 2 10.10.40.10:3306 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"

echo ""
echo "From Web (DMZ) namespace:"
echo -n "  → App:      "
sudo ip netns exec web curl -s -m 2 10.10.30.10:8080 > /dev/null 2>&1 && echo "✓ OK (allowed by firewall)" || echo "✗ FAIL"
echo -n "  → Database: "
sudo ip netns exec web curl -s -m 2 10.10.40.10:3306 > /dev/null 2>&1 && echo "✗ FAIL (expected)" || echo "✓ OK (blocked by firewall)"

echo ""
echo "From App (Internal) namespace:"
echo -n "  → Database: "
sudo ip netns exec app curl -s -m 2 10.10.40.10:3306 > /dev/null 2>&1 && echo "✓ OK (allowed by firewall)" || echo "✗ FAIL"
echo -n "  → Web:      "
sudo ip netns exec app curl -s -m 2 10.10.20.10:80 > /dev/null 2>&1 && echo "✗ FAIL (expected)" || echo "✓ OK (blocked by firewall)"

echo ""
echo "To stop services: sudo pkill -f 'nginx.*homelab'; pkill -f 'python3.*8080'; pkill -f 'python3.*3306'"
EOF

chmod +x scripts/05-start-services.sh

# Test it
sudo ./scripts/05-start-services.sh
```

**Expected Output:**
```
From Management namespace:
  → Web:      ✓ OK
  → App:      ✓ OK
  → Database: ✓ OK

From Web (DMZ) namespace:
  → App:      ✓ OK (allowed by firewall)
  → Database: ✓ OK (blocked by firewall)

From App (Internal) namespace:
  → Database: ✓ OK (allowed by firewall)
  → Web:      ✓ OK (blocked by firewall)
```

**Checkpoint:** Test manually
```bash
# From management - access web server
sudo ip netns exec mgmt curl 10.10.20.10
# Should see: "Web Server (DMZ)"

# From web - try to access database (should fail/timeout)
sudo ip netns exec web curl --max-time 3 10.10.40.10:3306
# Should timeout or fail

# From web - access app server (should work)
sudo ip netns exec web curl 10.10.30.10:8080
# Should see: "App Server (Internal)"
```

---

### Session 2.3: Create Master Setup Script (30 minutes)

**Goal:** One command to build everything

```bash
cat > scripts/setup-all.sh << 'EOF'
#!/bin/bash
#
# Master Setup Script
# Purpose: Build entire home lab network with one command
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/homelab-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log "=========================================="
log "Home Lab Network Setup"
log "=========================================="
log "Log file: $LOG_FILE"
log ""

# Step 1: Create namespaces
log "Step 1/6: Creating network namespaces..."
if bash "$SCRIPT_DIR/01-create-namespaces.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Namespaces created"
else
    log_error "Failed to create namespaces"
    exit 1
fi

# Step 2: Create veth pairs
log "Step 2/6: Creating virtual ethernet pairs..."
if bash "$SCRIPT_DIR/02-create-links.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Virtual links created"
else
    log_error "Failed to create links"
    exit 1
fi

# Step 3: Configure IP addresses
log "Step 3/6: Configuring IP addresses..."
if bash "$SCRIPT_DIR/03-configure-ips.sh" >> "$LOG_FILE" 2>&1; then
    log_success "IP addresses configured"
else
    log_error "Failed to configure IPs"
    exit 1
fi

# Step 4: Configure firewall
log "Step 4/6: Configuring firewall rules..."
if bash "$SCRIPT_DIR/04-configure-firewall.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Firewall configured"
else
    log_error "Failed to configure firewall"
    exit 1
fi

# Step 5: Start services
log "Step 5/6: Starting services..."
if bash "$SCRIPT_DIR/05-start-services.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Services started"
else
    log_warning "Some services may have failed to start"
fi

# Step 6: Final status check
log "Step 6/6: Running status check..."
bash "$SCRIPT_DIR/status.sh"

log ""
log "=========================================="
log_success "Setup Complete!"
log "=========================================="
log ""
log "Next steps:"
log "  - Review status: sudo ./scripts/status.sh"
log "  - Test manually: sudo ip netns exec mgmt bash"
log "  - View logs: cat $LOG_FILE"
log "  - Tear down: sudo ./scripts/destroy-all.sh"
EOF

chmod +x scripts/setup-all.sh
```

---

### Session 2.4: Create Status Check Script (15 minutes)

**Goal:** Easy way to verify lab state

```bash
cat > scripts/status.sh << 'EOF'
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
EOF

chmod +x scripts/status.sh
```

---

### Session 2.5: Create Teardown Script (10 minutes)

**Goal:** Clean way to destroy the lab

```bash
cat > scripts/destroy-all.sh << 'EOF'
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
EOF

chmod +x scripts/destroy-all.sh
```

---

### Session 2.6: Commit Day 2 Progress (5 minutes)

```bash
cd ~/homelab
git add scripts/
git commit -m "Day 2 complete: Security and services implemented"
```

---

## 🎉 Day 2 Complete!

**What you've accomplished:**
- ✅ Firewall rules with nftables
- ✅ Security zones implemented
- ✅ Web, App, and DB services running
- ✅ Master setup script
- ✅ Status check script
- ✅ Teardown script

**Current state:** Full multi-tier network with security controls!

---

## Day 3: Advanced Features & Monitoring (2-3 hours)

### Session 3.1: Network Troubleshooting Tools (45 minutes)

**Goal:** Learn to diagnose network issues

```bash
cat > docs/troubleshooting-guide.md << 'EOF'
# Troubleshooting Guide

## Quick Diagnostic Commands

### Check Namespace Status
```bash
# List all namespaces
ip netns list

# Enter a namespace interactively
sudo ip netns exec mgmt bash
# Now you're "inside" the mgmt namespace
# Exit with: exit
```

### Check Interfaces and IPs
```bash
# Show all interfaces in a namespace
sudo ip netns exec router ip addr

# Brief format (easier to read)
sudo ip netns exec router ip -br addr

# Check specific interface
sudo ip netns exec web ip addr show veth-web-r
```

### Check Routing
```bash
# Show routing table
sudo ip netns exec mgmt ip route

# Trace packet path
sudo ip netns exec mgmt traceroute 10.10.40.10

# Check if forwarding is enabled
sudo ip netns exec router sysctl net.ipv4.ip_forward
```

### Test Connectivity
```bash
# Basic ping
sudo ip netns exec mgmt ping -c 3 10.10.20.10

# Test specific port (using nc/netcat)
sudo ip netns exec mgmt nc -zv 10.10.20.10 80

# Test with timeout
sudo ip netns exec web ping -c 1 -W 2 10.10.30.10

# Test HTTP endpoint
sudo ip netns exec mgmt curl -v 10.10.20.10
```

### Packet Capture
```bash
# Capture on router interface (see all traffic)
sudo ip netns exec router tcpdump -i veth-r-web -n

# Capture specific traffic
sudo ip netns exec router tcpdump -i veth-r-web port 80

# Save to file
sudo ip netns exec router tcpdump -i veth-r-web -w /tmp/capture.pcap

# Read captured file
tcpdump -r /tmp/capture.pcap
```

### Firewall Debugging
```bash
# View all firewall rules
sudo ip netns exec router nft list ruleset

# View only forward chain
sudo ip netns exec router nft list chain ip filter forward

# Monitor dropped packets (check system logs)
sudo journalctl -f | grep "FIREWALL-DROP"

# Or check dmesg
sudo dmesg -T | grep "FIREWALL-DROP"
```

### Process Management
```bash
# Check running services
ps aux | grep nginx
ps aux | grep python3

# Kill specific service
sudo pkill -f "nginx.*homelab"

# Check service is listening
sudo ip netns exec web ss -tlnp | grep :80
```

## Common Issues and Solutions

### Issue: "Cannot create namespace: File exists"
**Solution:**
```bash
# Namespace already exists, delete it first
sudo ip netns del router
# Or tear down everything
sudo ./scripts/destroy-all.sh
```

### Issue: "Cannot ping between namespaces"
**Diagnostic steps:**
```bash
# 1. Check interfaces are up
sudo ip netns exec router ip link show

# 2. Check IPs are assigned
sudo ip netns exec mgmt ip addr

# 3. Check routing
sudo ip netns exec mgmt ip route

# 4. Check forwarding enabled
sudo ip netns exec router sysctl net.ipv4.ip_forward

# 5. Capture packets to see what's happening
sudo ip netns exec router tcpdump -i veth-r-mgmt icmp
```

### Issue: "Web can't reach App even though firewall allows it"
**Diagnostic steps:**
```bash
# 1. Verify firewall rules
sudo ip netns exec router nft list ruleset | grep 8080

# 2. Check if app server is running
ps aux | grep "python3.*8080"

# 3. Test from web namespace with packet capture
# Terminal 1:
sudo ip netns exec router tcpdump -i veth-r-app port 8080
# Terminal 2:
sudo ip netns exec web curl 10.10.30.10:8080

# 4. Check if app is listening on correct IP
sudo ip netns exec app ss -tlnp | grep 8080
```

### Issue: "Services won't start"
**Solution:**
```bash
# Kill any existing processes
sudo pkill -f nginx
sudo pkill -f python3

# Check for port conflicts
sudo ip netns exec web ss -tlnp

# Start services manually to see errors
sudo ip netns exec web nginx -c ~/homelab/configs/nginx-web.conf
```

## Advanced Troubleshooting

### Watching Live Traffic
```bash
# Watch HTTP requests in real-time
sudo ip netns exec router tcpdump -i veth-r-web -A 'tcp port 80'

# Watch connection attempts
sudo ip netns exec router tcpdump -i veth-r-web 'tcp[tcpflags] & (tcp-syn) != 0'

# See dropped packets
sudo ip netns exec router tcpdump -i veth-r-db -n
# Then try blocked connection from another terminal
```

### Performance Testing
```bash
# Use iperf3 (install if needed: dnf install iperf3)
# Server side:
sudo ip netns exec web iperf3 -s

# Client side:
sudo ip netns exec mgmt iperf3 -c 10.10.20.10

# HTTP load testing with curl
for i in {1..10}; do sudo ip netns exec mgmt curl -s 10.10.20.10 > /dev/null; done
```

### Network Statistics
```bash
# Show interface statistics
sudo ip netns exec router ip -s link show veth-r-web

# Show connection states
sudo ip netns exec router ss -s

# Show routing cache
sudo ip netns exec router ip route show cache
```
EOF

git add docs/troubleshooting-guide.md
git commit -m "Add comprehensive troubleshooting guide"
```

---

### Session 3.2: Create Monitoring Script (30 minutes)

**Goal:** Real-time network monitoring

```bash
cat > scripts/monitor.sh << 'EOF'
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
EOF

chmod +x scripts/monitor.sh

# Test it
sudo ./scripts/monitor.sh test
```

---

### Session 3.3: Create Network Lab Scenarios (45 minutes)

**Goal:** Practice scenarios for learning

```bash
cat > docs/lab-scenarios.md << 'EOF'
# Lab Scenarios

Practice scenarios to build your skills.

## Scenario 1: Block Unauthorized Access

**Goal:** Modify firewall to block App from accessing Web server

```bash
# Current state: No rule prevents this
sudo ip netns exec app curl 10.10.20.10
# This works but shouldn't in a real environment

# Solution: Add explicit deny rule
sudo ip netns exec router nft add rule ip filter forward \
    ip saddr 10.10.30.0/24 ip daddr 10.10.20.0/24 drop

# Verify
sudo ip netns exec app curl --max-time 3 10.10.20.10
# Should timeout

# Clean up (remove the rule)
sudo ip netns exec router nft delete rule ip filter forward handle <handle_number>
```

## Scenario 2: Add Rate Limiting

**Goal:** Limit connections to web server

```bash
# Add rate limit (max 10 connections per minute)
sudo ip netns exec router nft add rule ip filter forward \
    ip daddr 10.10.20.10 tcp dport 80 \
    limit rate 10/minute accept

# Test with rapid requests
for i in {1..20}; do 
    sudo ip netns exec mgmt curl -s 10.10.20.10 & 
done
# Some should be blocked after limit is reached
```

## Scenario 3: Add Logging for Specific Traffic

**Goal:** Log all database connections

```bash
# Add logging before database access rule
sudo ip netns exec router nft insert rule ip filter forward \
    ip daddr 10.10.40.10 tcp dport 3306 \
    log prefix '"[DB-ACCESS] "' level info

# Test connection
sudo ip netns exec app curl 10.10.40.10:3306

# View logs
sudo dmesg -T | grep "DB-ACCESS"
# Or
sudo journalctl -f | grep "DB-ACCESS"
```

## Scenario 4: Simulate Network Failure

**Goal:** Take down a link and observe behavior

```bash
# Bring down link between router and app
sudo ip netns exec router ip link set veth-r-app down

# Test connectivity
sudo ip netns exec mgmt ping 10.10.30.10
# Should fail

# Check what's happening
sudo ip netns exec router ip link show veth-r-app
# Shows "state DOWN"

# Bring it back up
sudo ip netns exec router ip link set veth-r-app up

# Verify recovery
sudo ip netns exec mgmt ping -c 3 10.10.30.10
```

## Scenario 5: Add NAT for Outbound Connectivity

**Goal:** Allow internal hosts to reach external network (simulated)

```bash
# Add a bridge to connect to host network
sudo ip link add br0 type bridge
sudo ip link set br0 up
sudo ip addr add 192.168.100.1/24 dev br0

# Connect router to bridge
sudo ip link add veth-r-ext type veth peer name veth-ext-r
sudo ip link set veth-r-ext netns router
sudo ip link set veth-ext-r master br0
sudo ip link set veth-ext-r up
sudo ip netns exec router ip link set veth-r-ext up
sudo ip netns exec router ip addr add 192.168.100.2/24 dev veth-r-ext

# Add NAT rule
sudo ip netns exec router nft add table ip nat
sudo ip netns exec router nft add chain ip nat postrouting \
    '{ type nat hook postrouting priority 100; }'
sudo ip netns exec router nft add rule ip nat postrouting \
    ip saddr 10.10.0.0/16 oifname "veth-r-ext" masquerade

# Add default route in router
sudo ip netns exec router ip route add default via 192.168.100.1

# Test (if host has internet)
sudo ip netns exec mgmt ping 8.8.8.8
```

## Scenario 6: Packet Capture During Attack

**Goal:** Capture and analyze suspicious traffic

```bash
# Start capture on DMZ interface
sudo ip netns exec router tcpdump -i veth-r-web -w /tmp/dmz-traffic.pcap &
TCPDUMP_PID=$!

# Simulate various types of traffic
# Normal traffic
sudo ip netns exec mgmt curl 10.10.20.10

# Port scan simulation
for port in {79..82}; do
    sudo ip netns exec mgmt nc -zv -w 1 10.10.20.10 $port 2>&1
done

# Stop capture
sudo kill $TCPDUMP_PID

# Analyze
tcpdump -r /tmp/dmz-traffic.pcap -n | less
```

## Scenario 7: Add Second Web Server (Load Balancing Prep)

**Goal:** Add redundancy to DMZ

```bash
# Create second web namespace
sudo ip netns add web2

# Create link
sudo ip link add veth-r-web2 type veth peer name veth-web2-r
sudo ip link set veth-r-web2 netns router
sudo ip link set veth-web2-r netns web2
sudo ip netns exec router ip link set veth-r-web2 up
sudo ip netns exec web2 ip link set veth-web2-r up
sudo ip netns exec web2 ip link set lo up

# Configure IP (same subnet, different host)
sudo ip netns exec router ip addr add 10.10.20.2/24 dev veth-r-web2
sudo ip netns exec web2 ip addr add 10.10.20.11/24 dev veth-web2-r
sudo ip netns exec web2 ip route add default via 10.10.20.2

# Start second nginx
cat > /tmp/nginx-web2.conf << 'NGINX_EOF'
daemon off;
error_log /tmp/nginx-web2-error.log info;
pid /tmp/nginx-web2.pid;
events { worker_connections 1024; }
http {
    access_log /tmp/nginx-web2-access.log;
    server {
        listen 10.10.20.11:80;
        location / {
            return 200 "Web Server 2 (DMZ)\nVLAN: 20\nIP: 10.10.20.11\n";
            add_header Content-Type text/plain;
        }
    }
}
NGINX_EOF

sudo ip netns exec web2 nginx -c /tmp/nginx-web2.conf &

# Test both servers
sudo ip netns exec mgmt curl 10.10.20.10
sudo ip netns exec mgmt curl 10.10.20.11
```

## Scenario 8: Implement Connection Tracking

**Goal:** Monitor who's connecting to what

```bash
# View current connections
sudo ip netns exec router cat /proc/net/nf_conntrack

# Or with conntrack tool (install if needed)
sudo dnf install -y conntrack-tools
sudo ip netns exec router conntrack -L

# Watch connections in real-time
sudo ip netns exec router conntrack -E &

# Generate traffic
sudo ip netns exec mgmt curl 10.10.20.10

# See the connection establishment and teardown
```

## Challenge Scenarios

### Challenge 1: Geo-based Blocking (Simulated)
Create a new VLAN for "external" traffic and block it from accessing database.

### Challenge 2: Intrusion Detection
Use tcpdump to detect port scanning and create alerts.

### Challenge 3: High Availability
Set up two routers with VRRP (keepalived) for failover.

### Challenge 4: VPN Tunnel
Create a WireGuard tunnel between two "sites" (different network namespaces).

### Challenge 5: DNS Resolution
Set up BIND or dnsmasq so hosts can use names instead of IPs.
EOF

git add docs/lab-scenarios.md
git commit -m "Add practice scenarios"
```

---

### Session 3.4: Create Testing Script (20 minutes)

**Goal:** Automated testing suite

```bash
cat > scripts/run-tests.sh << 'EOF'
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
NC='\033[0m'

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
run_test "Router namespace exists" "ip netns list | grep -q '^router"
run_test "Mgmt namespace exists" "ip netns list | grep -q '^mgmt"
run_test "Web namespace exists" "ip netns list | grep -q '^web"
run_test "App namespace exists" "ip netns list | grep -q '^app"
run_test "DB namespace exists" "ip netns list | grep -q '^db"
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
```bash
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
EOF

chmod +x scripts/run-tests.sh

# Test it
sudo ./scripts/run-tests.sh
```

Expected Output:
```
========================================
Running Test Suite
========================================

Namespace Tests:
Testing: Router namespace exists ... PASS
Testing: Mgmt namespace exists ... PASS
Testing: Web namespace exists ... PASS
Testing: App namespace exists ... PASS
Testing: DB namespace exists ... PASS

Interface Tests:
Testing: Router has mgmt interface ... PASS
Testing: Router has web interface ... PASS
Testing: Router has app interface ... PASS
Testing: Router has db interface ... PASS

IP Configuration Tests:
Testing: Mgmt has correct IP ... PASS
Testing: Web has correct IP ... PASS
Testing: App has correct IP ... PASS
Testing: DB has correct IP ... PASS
Testing: Router mgmt IP ... PASS

Routing Tests:
Testing: Mgmt default route ... PASS
Testing: Web default route ... PASS
Testing: App default route ... PASS
Testing: DB default route ... PASS

Allowed Connectivity Tests:
Testing: Mgmt → Web ping ... PASS
Testing: Mgmt → App ping ... PASS
Testing: Mgmt → DB ping ... PASS
Testing: Web → App HTTP ... PASS
Testing: App → DB HTTP ... PASS

Blocked Connectivity Tests:
Testing: Web → DB ping (blocked) ... PASS
Testing: App → Web HTTP (blocked) ... PASS

Firewall Tests:
Testing: Firewall chain exists ... PASS
Testing: Management allow rule ... PASS
Testing: DMZ to Internal rule ... PASS
Testing: Internal to DB rule ... PASS

Service Tests:
Testing: Web server listening ... PASS
Testing: App server listening ... PASS
Testing: DB server listening ... PASS
Testing: Nginx process running ... PASS
Testing: App Python process running ... PASS
Testing: DB Python process running ... PASS

========================================
Test Summary
========================================
Passed: 28 | Failed: 0
All tests passed! Lab is healthy.
```

Checkpoint: Run the test suite—aim for all PASS. If any fail, refer to docs/troubleshooting-guide.md.

---

### Session 3.5: Advanced Routing with FRR (30 minutes)
**Goal:** Add dynamic routing for scalability (optional enhancement)

```bash
# Install and configure FRR if not already (from Day 1)
sudo dnf install -y frr
sudo systemctl enable --now frr

# Create FRR config for router namespace
cat > configs/frr-router.conf << 'EOF'
frr version 8.4
frr defaults traditional
hostname router
log syslog informational
!
interface veth-r-mgmt
 ip address 10.10.10.1/24
!
interface veth-r-web
 ip address 10.10.20.1/24
!
interface veth-r-app
 ip address 10.10.30.1/24
!
interface veth-r-db
 ip address 10.10.40.1/24
!
router ospf
 ospf router-id 10.10.10.1
 network 10.10.10.0/24 area 0
 network 10.10.20.0/24 area 0
 network 10.10.30.0/24 area 0
 network 10.10.40.0/24 area 0
!
EOF

# Script to start FRR in router
cat > scripts/06-start-frr.sh << 'EOF'
#!/bin/bash
#
# Script 6: Start FRR Dynamic Routing
#

set -euo pipefail

echo "=== Starting FRR OSPF Routing ==="

# Copy config to router namespace
sudo ip netns exec router cp /home/$USER/homelab/configs/frr-router.conf /etc/frr/frr.conf
sudo ip netns exec router chown frr:frr /etc/frr/frr.conf

# Start FRR in router namespace (use vtysh for config)
sudo ip netns exec router frr /etc/frr/frr.conf > /dev/null 2>&1 &
sleep 3

echo "  ✓ FRR started with OSPF"

echo ""
echo "Verify OSPF neighbors (should show connected subnets):"
sudo ip netns exec router vtysh -c "show ip ospf neighbor"
echo ""
echo "Routing table with OSPF:"
sudo ip netns exec router vtysh -c "show ip route"
EOF

chmod +x scripts/06-start-frr.sh

# Test it (after running setup-all.sh)
sudo ./scripts/06-start-frr.sh
```

Expected Output:
```
=== Starting FRR OSPF Routing ===
  ✓ FRR started with OSPF

Verify OSPF neighbors (should show connected subnets):

Routing table with OSPF:
O>* 10.10.10.0/24 [110/20] via 10.10.10.1, veth-r-mgmt, 00:00:05, intra-area
... (similar for other subnets)
```

Checkpoint: OSPF should advertise routes dynamically. Test by removing a static route (if added) and verifying connectivity persists.

Update setup-all.sh to include FRR (optional—add after Step 5):
```bash
# In setup-all.sh, after "Starting services...", add:
log "Step 5.5/6: Starting dynamic routing..."
if bash "$SCRIPT_DIR/06-start-frr.sh" >> "$LOG_FILE" 2>&1; then
    log_success "FRR started"
else
    log_warning "FRR startup skipped"
fi
```

```bash
# Commit the enhancement
git add configs/ scripts/06-start-frr.sh
git commit -m "Add FRR OSPF dynamic routing"
```

---

### Session 3.6: Project Wrap-Up and Documentation (15 minutes)
**Goal:** Finalize docs, run full tests, and plan next steps

```bash
# Update README with full usage
cat >> README.md << 'EOF'

## Architecture Diagram (ASCII)
```
                +-----------------+
                |   Router NS     |
                | 10.10.x.1 GWs   |
                +--------+--------+
                         |
    +--------------------+--------------------+
    |                    |                    |
+----+----+         +----+----+         +----+----+
| Mgmt NS |         | Web NS  |         | App NS  |
|10.10.10.10|       |10.10.20.10|       |10.10.30.10|
+----------+       +----------+       +----------+
                         |                    |
                   +--------------------+         |
                   |                    |         |
              +----+----+         +----+----+      |
              | DB NS   |         (Firewall)       |
              |10.10.40.10|                       |
              +----------+                       |
```

## Usage
1. **Build Lab:** `sudo ./scripts/setup-all.sh`
2. **Check Status:** `sudo ./scripts/status.sh`
3. **Run Tests:** `sudo ./scripts/run-tests.sh`
4. **Monitor:** `sudo ./scripts/monitor.sh traffic`
5. **Troubleshoot:** See `docs/troubleshooting-guide.md`
6. **Scenarios:** See `docs/lab-scenarios.md`
7. **Teardown:** `sudo ./scripts/destroy-all.sh`

## Advanced
- Dynamic Routing: Run `./scripts/06-start-frr.sh`
- Custom Scenarios: Edit firewall with `nft` commands

## Troubleshooting
Common issues: Check `docs/troubleshooting-guide.md`
EOF

# Final full test
sudo ./scripts/destroy-all.sh  # Clean slate
sudo ./scripts/setup-all.sh    # Rebuild
sudo ./scripts/run-tests.sh    # Verify
sudo ./scripts/status.sh       # Quick check

# Commit final docs
git add README.md
git commit -m "Finalize README and project wrap-up"
```

Checkpoint: Entire lab builds and tests in <5 minutes. Push to GitHub if desired: `git remote add origin <your-repo>; git push -u origin main`.

---

🎉 Day 3 Complete!
What you've accomplished:

* ✅ Comprehensive troubleshooting guide
* ✅ Real-time monitoring tools
* ✅ Hands-on lab scenarios for practice
* ✅ Automated test suite
* ✅ Optional dynamic routing with FRR
* ✅ Polished documentation and wrap-up

### Overall Project Summary
**Total Time:** 6-9 hours over 3 days  
**Key Skills Gained:**
- Linux network namespaces for simulation
- VLAN-like segmentation with veth pairs
- Static/dynamic routing (ip route + FRR/OSPF)
- Stateful firewalls (nftables)
- Service deployment and troubleshooting (tcpdump, ss, curl)
- Automation with Bash scripting and Git

**Next Level Ideas:**
- Integrate containers: Use Docker with Calico CNI for pod networking.
- SDN: Add Open vSwitch for VXLAN overlays.
- Monitoring: Prometheus + Grafana for metrics.
- Security: Add IPSec tunnels or Falco for runtime security.

Your home lab is now a production-like multi-tier environment! Run `sudo ./scripts/setup-all.sh` anytime to spin it up. If you extend it (e.g., add BGP peering), share your mods—happy labbing! What's your first scenario to try?
