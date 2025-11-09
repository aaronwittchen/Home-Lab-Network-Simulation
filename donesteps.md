chmod +x scripts/monitor.sh
sudo ./scripts/monitor.sh test

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



chmod +x scripts/run-tests.sh

# Test it
sudo ./scripts/run-tests.sh

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
