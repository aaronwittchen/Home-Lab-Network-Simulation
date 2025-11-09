### 1. **Home Lab Network Simulation**
Build a multi-tier network environment:
- Set up VLANs using network namespaces
- Configure routing between subnets (static routes, dynamic routing with FRR/BIRD)
- Implement firewall rules (iptables/nftables)
- Set up NAT, port forwarding
- Practice network troubleshooting (tcpdump, wireshark, ss, ip commands)

# Home Lab Network Simulation - Production-Style Setup Guide

## 🎯 Project Goal
Build a realistic multi-tier datacenter network simulation on Rocky Linux using industry-standard practices.

---

## 📐 Network Design

### Topology
```
                    Internet (Simulated)
                            |
                    ┌───────┴───────┐
                    │   Gateway/FW  │ 192.168.100.1
                    │   (Physical)  │
                    └───────┬───────┘
                            |
                    ┌───────┴───────┐
                    │  Core Router  │ 
                    │   (netns)     │
                    └───┬───┬───┬───┘
                        |   |   |
        ┌───────────────┴───┴───┴──────────────┐
        |               |         |            |
    VLAN 10         VLAN 20   VLAN 30      VLAN 40
  Management         DMZ      Internal    Database
  10.10.10.0/24   10.10.20.0/24  10.10.30.0/24  10.10.40.0/24
        |               |         |            |
   ┌────┴────┐    ┌────┴────┐ ┌──┴───┐    ┌───┴────┐
   │ Jump    │    │ Web     │ │ App  │    │ DB     │
   │ Host    │    │ Server  │ │ Srv  │    │ Server │
   └─────────┘    └─────────┘ └──────┘    └────────┘
```

### IP Addressing Scheme
```
VLAN ID | Name        | Subnet          | Gateway    | Purpose
--------|-------------|-----------------|------------|------------------
10      | Management  | 10.10.10.0/24   | 10.10.10.1 | Admin/Jump hosts
20      | DMZ         | 10.10.20.0/24   | 10.10.20.1 | Public-facing web
30      | Internal    | 10.10.30.0/24   | 10.10.30.1 | Application tier
40      | Database    | 10.10.40.0/24   | 10.10.40.1 | Database servers

Host Allocations:
- .1        = Gateway (router)
- .2-.9     = Reserved (future network devices)
- .10-.99   = Servers
- .100-.199 = Dynamic hosts (DHCP pool)
- .200-.254 = Reserved
```

### Firewall Policy (Security Zones)
```
Zone: Management (VLAN 10)
  - Can access: ALL zones
  - Incoming: SSH from specific IPs only
  
Zone: DMZ (VLAN 20)
  - Can access: Internal (VLAN 30) on port 8080 only
  - Incoming: HTTP/HTTPS from anywhere
  
Zone: Internal (VLAN 30)
  - Can access: Database (VLAN 40) on port 3306 only
  - Incoming: Only from DMZ
  
Zone: Database (VLAN 40)
  - Can access: Nothing
  - Incoming: Only from Internal on port 3306
```

---

## 🛠️ Implementation Method

**Real datacenters use:** Physical servers with VLANs on network switches

**Our equivalent:** Network namespaces (closest simulation without buying hardware)

**Why namespaces?**
- Industry uses similar concepts (containers, VRFs on routers)
- Lightweight, runs on single VM
- Teaches actual Linux networking, not abstracted VM networking
- Same commands/concepts as production systems

---

## 📦 Initial Setup

### 1. Install Required Packages
```bash
# Core networking
sudo dnf install -y iproute iptables-services nftables bridge-utils

# Monitoring & troubleshooting
sudo dnf install -y tcpdump wireshark-cli mtr traceroute bind-utils net-tools

# Services
sudo dnf install -y nginx dnsmasq frr

# Documentation & automation
sudo dnf install -y git vim tmux
```

### 2. Enable IP Forwarding
```bash
# Temporary (this session only)
sudo sysctl -w net.ipv4.ip_forward=1

# Permanent (survives reboot)
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

### 3. Create Project Directory Structure
```bash
mkdir -p ~/homelab/{scripts,configs,docs,monitoring}
cd ~/homelab
git init

# Create README
cat > README.md << 'EOF'
# Home Lab Network Simulation

Multi-tier datacenter network simulation using Linux network namespaces.

## Architecture
- 4 VLANs (Management, DMZ, Internal, Database)
- Central router with firewall rules
- Service: Web → App → Database architecture

## Quick Start
```
./scripts/setup-all.sh    # Build entire lab
./scripts/destroy-all.sh  # Tear down lab
./scripts/status.sh       # Check status
```

## Documentation
See docs/ folder for detailed setup and troubleshooting guides.
EOF

git add README.md
git commit -m "Initial commit: Project structure"
```

---

## 🔧 Build Scripts (Production Style)

### Master Setup Script
**File:** `scripts/setup-all.sh`
```bash
#!/bin/bash
#
# Master setup script for home lab network
# Usage: sudo ./scripts/setup-all.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/homelab-setup.log"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log "ERROR: This script must be run as root"
   exit 1
fi

log "=== Starting Home Lab Network Setup ==="

# Step 1: Create namespaces
log "Step 1: Creating network namespaces..."
bash "$SCRIPT_DIR/01-create-namespaces.sh" || exit 1

# Step 2: Create veth pairs
log "Step 2: Creating virtual ethernet pairs..."
bash "$SCRIPT_DIR/02-create-links.sh" || exit 1

# Step 3: Configure IP addresses
log "Step 3: Configuring IP addresses..."
bash "$SCRIPT_DIR/03-configure-ips.sh" || exit 1

# Step 4: Configure routing
log "Step 4: Setting up routing..."
bash "$SCRIPT_DIR/04-configure-routing.sh" || exit 1

# Step 5: Configure firewall
log "Step 5: Configuring firewall rules..."
bash "$SCRIPT_DIR/05-configure-firewall.sh" || exit 1

# Step 6: Start services
log "Step 6: Starting services..."
bash "$SCRIPT_DIR/06-start-services.sh" || exit 1

log "=== Setup Complete ==="
log "Run './scripts/status.sh' to verify setup"
```

### Script 1: Create Namespaces
**File:** `scripts/01-create-namespaces.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Creating network namespaces..."

# Create namespaces (like creating separate virtual routers/servers)
ip netns add router
ip netns add mgmt
ip netns add web
ip netns add app
ip netns add db

# Enable loopback in each namespace
for ns in router mgmt web app db; do
    ip netns exec $ns ip link set lo up
done

echo "Created namespaces:"
ip netns list
```

### Script 2: Create Virtual Links
**File:** `scripts/02-create-links.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Creating veth pairs (virtual network cables)..."

# Router <-> Management
ip link add veth-r-mgmt type veth peer name veth-mgmt-r
ip link set veth-r-mgmt netns router
ip link set veth-mgmt-r netns mgmt

# Router <-> Web (DMZ)
ip link add veth-r-web type veth peer name veth-web-r
ip link set veth-r-web netns router
ip link set veth-web-r netns web

# Router <-> App
ip link add veth-r-app type veth peer name veth-app-r
ip link set veth-r-app netns router
ip link set veth-app-r netns app

# Router <-> DB
ip link add veth-r-db type veth peer name veth-db-r
ip link set veth-r-db netns router
ip link set veth-db-r netns db

# Bring all interfaces up
for ns in router mgmt web app db; do
    for iface in $(ip netns exec $ns ip link show | grep veth | awk -F: '{print $2}' | tr -d ' '); do
        ip netns exec $ns ip link set $iface up
    done
done

echo "veth pairs created and enabled"
```

### Script 3: Configure IPs
**File:** `scripts/03-configure-ips.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Configuring IP addresses..."

# Router interfaces (gateway for each VLAN)
ip netns exec router ip addr add 10.10.10.1/24 dev veth-r-mgmt
ip netns exec router ip addr add 10.10.20.1/24 dev veth-r-web
ip netns exec router ip addr add 10.10.30.1/24 dev veth-r-app
ip netns exec router ip addr add 10.10.40.1/24 dev veth-r-db

# Host interfaces
ip netns exec mgmt ip addr add 10.10.10.10/24 dev veth-mgmt-r
ip netns exec web ip addr add 10.10.20.10/24 dev veth-web-r
ip netns exec app ip addr add 10.10.30.10/24 dev veth-app-r
ip netns exec db ip addr add 10.10.40.10/24 dev veth-db-r

# Default routes (point to router)
ip netns exec mgmt ip route add default via 10.10.10.1
ip netns exec web ip route add default via 10.10.20.1
ip netns exec app ip route add default via 10.10.30.1
ip netns exec db ip route add default via 10.10.40.1

echo "IP configuration complete"
echo ""
echo "Network assignments:"
echo "  Management: 10.10.10.10"
echo "  Web (DMZ):  10.10.20.10"
echo "  App:        10.10.30.10"
echo "  Database:   10.10.40.10"
```

### Script 4: Configure Routing
**File:** `scripts/04-configure-routing.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Enabling IP forwarding in router namespace..."

# Enable forwarding in router (makes it act like a router)
ip netns exec router sysctl -w net.ipv4.ip_forward=1

echo "Routing configured"
echo ""
echo "Testing connectivity..."
echo "  Mgmt → Web:  $(ip netns exec mgmt ping -c 1 -W 1 10.10.20.10 > /dev/null 2>&1 && echo 'OK' || echo 'FAIL')"
echo "  Web → App:   $(ip netns exec web ping -c 1 -W 1 10.10.30.10 > /dev/null 2>&1 && echo 'OK' || echo 'FAIL')"
echo "  App → DB:    $(ip netns exec app ping -c 1 -W 1 10.10.40.10 > /dev/null 2>&1 && echo 'OK' || echo 'FAIL')"
```

### Script 5: Configure Firewall
**File:** `scripts/05-configure-firewall.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Configuring firewall rules..."

# Use nftables (modern standard in RHEL 8+)
ip netns exec router nft add table ip filter
ip netns exec router nft add chain ip filter forward '{ type filter hook forward priority 0; policy drop; }'

# Allow established/related connections
ip netns exec router nft add rule ip filter forward ct state established,related accept

# Management VLAN can access everything
ip netns exec router nft add rule ip filter forward ip saddr 10.10.10.0/24 accept

# DMZ (Web) → Internal (App) on port 8080
ip netns exec router nft add rule ip filter forward ip saddr 10.10.20.0/24 ip daddr 10.10.30.0/24 tcp dport 8080 accept

# Internal (App) → Database on port 3306
ip netns exec router nft add rule ip filter forward ip saddr 10.10.30.0/24 ip daddr 10.10.40.0/24 tcp dport 3306 accept

# Log dropped packets (for troubleshooting)
ip netns exec router nft add rule ip filter forward log prefix \"[FW-DROP] \" drop

echo "Firewall rules applied"
echo ""
echo "Ruleset:"
ip netns exec router nft list ruleset
```

### Script 6: Start Services
**File:** `scripts/06-start-services.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Starting services in namespaces..."

# Web server in DMZ
ip netns exec web nginx -c /dev/stdin << 'EOF'
daemon off;
error_log /dev/stdout info;
events { worker_connections 1024; }
http {
    access_log /dev/stdout;
    server {
        listen 10.10.20.10:80;
        location / {
            return 200 "Web Server (DMZ) - VLAN 20\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF &

# Simple HTTP server for app tier
ip netns exec app python3 -m http.server 8080 --bind 10.10.30.10 > /dev/null 2>&1 &

echo "Services started"
echo ""
echo "Test URLs:"
echo "  Web: curl 10.10.20.10 (from mgmt namespace)"
echo "  App: curl 10.10.30.10:8080 (from web namespace)"
```

### Status Check Script
**File:** `scripts/status.sh`
```bash
#!/bin/bash

echo "=== Home Lab Network Status ==="
echo ""

echo "Namespaces:"
ip netns list
echo ""

echo "Router interfaces:"
ip netns exec router ip -br addr
echo ""

echo "Connectivity tests:"
echo -n "  Mgmt → Web:  "
ip netns exec mgmt ping -c 1 -W 1 10.10.20.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"

echo -n "  Web → App:   "
ip netns exec web ping -c 1 -W 1 10.10.30.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"

echo -n "  App → DB:    "
ip netns exec app ping -c 1 -W 1 10.10.40.10 > /dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL"

echo ""
echo "Firewall rules:"
ip netns exec router nft list ruleset | grep -A 20 "chain forward"
```

### Teardown Script
**File:** `scripts/destroy-all.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Tearing down home lab network..."

# Kill any processes running in namespaces
killall nginx 2>/dev/null || true
pkill -f "python3 -m http.server" 2>/dev/null || true

# Delete namespaces (this automatically deletes the veth pairs)
for ns in router mgmt web app db; do
    ip netns del $ns 2>/dev/null || true
done

echo "Lab torn down"
ip netns list
```

---

## 🚀 Usage

### Make scripts executable
```bash
chmod +x scripts/*.sh
```

### Build the lab
```bash
sudo ./scripts/setup-all.sh
```

### Check status
```bash
sudo ./scripts/status.sh
```

### Test connectivity
```bash
# Enter management namespace (like SSH-ing to jump host)
sudo ip netns exec mgmt bash

# Now you're "on" the management server
ping 10.10.20.10  # Ping web server
curl 10.10.20.10  # Access web server
exit

# Test from web to app
sudo ip netns exec web curl 10.10.30.10:8080
```

### Tear down
```bash
sudo ./scripts/destroy-all.sh
```

---

## 📚 Next Steps (Phase 2)

1. **Add dynamic routing (FRR with OSPF)**
2. **Implement proper DNS (BIND9)**
3. **Add monitoring (Prometheus node_exporter in each namespace)**
4. **Create Ansible playbooks to automate this**
5. **Add VPN between "sites" (WireGuard)**
6. **Implement HA with VRRP (keepalived)**

---

## 🔍 Troubleshooting Commands

```bash
# List all namespaces
ip netns list

# Show interfaces in a namespace
ip netns exec router ip addr

# Show routes in a namespace
ip netns exec web ip route

# Check firewall rules
ip netns exec router nft list ruleset

# Packet capture
ip netns exec web tcpdump -i veth-web-r

# Test specific port
ip netns exec mgmt nc -zv 10.10.20.10 80
```

---

This is **production-style**: modular scripts, logging, error handling, documentation, and version control. Exactly how you'd see it in a real datacenter automation repo.

Want me to create an artifact with all these scripts ready to copy?