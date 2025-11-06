# Network Design Documentation

> **Home Lab Network Simulation - Detailed Architecture Specification**

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Design Philosophy](#design-philosophy)
3. [Network Topology](#network-topology)
4. [IP Addressing Scheme](#ip-addressing-scheme)
5. [Security Architecture](#security-architecture)
6. [Routing Design](#routing-design)
7. [Service Architecture](#service-architecture)
8. [Implementation Details](#implementation-details)
9. [Scalability & Future Growth](#scalability--future-growth)
10. [Design Decisions & Trade-offs](#design-decisions--trade-offs)

---

## Executive Summary

This document outlines the network architecture for a multi-tier datacenter simulation using Linux network namespaces. It incorporates standard security zones, defense-in-depth measures, and common networking practices for enterprise settings.

**Key Characteristics:**
- **Security-First Design:** Defense in depth with multiple security zones
- **Zero-Trust Approach:** Default deny, explicit allow rules
- **Scalability:** Room for 89 hosts per VLAN, expandable design
- **High Availability Ready:** Architecture supports future HA implementations
- **Monitoring-Friendly:** Built for observability and troubleshooting

**Target Use Cases:**
- Multi-tier web applications (Web → App → Database)
- Microservices architectures
- Security testing and penetration testing labs
- Network engineering training
- Infrastructure automation development

---

## Design Philosophy

### Core Principles

#### 1. **Least Privilege Access**
Each security zone has minimal required access to other zones. No direct database access from DMZ, no outbound connectivity from database tier.

**Rationale:** Limits the impact of security breaches. A compromised web server cannot directly access sensitive data.

#### 2. **Defense in Depth**
Multiple layers of security controls:
- Network segmentation (VLANs)
- Stateful firewall (nftables)
- Service-level access control
- Future: Host-based firewalls, SELinux policies

**Rationale:** A single control failure does not compromise the entire network.

#### 3. **Explicit Allow Model**
Default policy is DROP. Only explicitly defined traffic flows are permitted.

**Rationale:** More secure than blacklist approach, easier to audit, follows zero-trust principles.

#### 4. **Operational Excellence**
Design emphasizes monitoring, logging, and troubleshooting capabilities.

**Rationale:** Network issues will occur; design must support rapid diagnosis and resolution.

### Real-World Equivalents

| Lab Component | Enterprise Equivalent |
|--------------|----------------------|
| Network Namespaces | VMs, Containers, Physical Servers |
| veth Pairs | Physical Network Cables, Trunk Ports |
| Router Namespace | Core Switch, Router, L3 Switch |
| nftables Firewall | Palo Alto, Cisco ASA, Fortinet FortiGate |
| Security Zones | DMZ, Trusted, Untrusted Networks |
| Management VLAN | OOB Management Network |

---

## Network Topology

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Physical Host (Rocky Linux)                 │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                     Router Namespace                        │ │
│  │               (Central Routing & Firewall)                  │ │
│  │                                                              │ │
│  │    veth-r-mgmt    veth-r-web    veth-r-app    veth-r-db   │ │
│  │       │               │              │             │        │ │
│  │   10.10.10.1     10.10.20.1    10.10.30.1   10.10.40.1    │ │
│  └───────┼───────────────┼──────────────┼─────────────┼───────┘ │
│          │               │              │             │          │
│  ┌───────┼───────┬───────┼──────┬───────┼──────┬──────┼────────┐│
│  │       │       │       │      │       │      │      │        ││
│  │ ┌─────▼────┐  │ ┌─────▼────┐ │ ┌─────▼────┐ │ ┌────▼─────┐ ││
│  │ │   mgmt   │  │ │   web    │ │ │   app    │ │ │    db    │ ││
│  │ │Namespace │  │ │Namespace │ │ │Namespace │ │ │Namespace │ ││
│  │ │          │  │ │          │ │ │          │ │ │          │ ││
│  │ │veth-mgmt-r  │ │veth-web-r│ │ │veth-app-r│ │ │veth-db-r │ ││
│  │ │10.10.10.10│ │ │10.10.20.10│ │ │10.10.30.10│ │10.10.40.10│ ││
│  │ │          │  │ │          │ │ │          │ │ │          │ ││
│  │ │ Jump Host│  │ │  Nginx   │ │ │ Python   │ │ │ Python   │ ││
│  │ │          │  │ │  Web Srv │ │ │  HTTP    │ │ │  Mock DB │ ││
│  │ └──────────┘  │ └──────────┘ │ └──────────┘ │ └──────────┘ ││
│  │               │              │              │              ││
│  │   VLAN 10     │    VLAN 20   │   VLAN 30    │   VLAN 40    ││
│  │  Management   │      DMZ     │   Internal   │   Database   ││
│  └───────────────┴──────────────┴──────────────┴──────────────┘│
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Detailed Topology Map

```
Internet (Simulated - Future Extension)
    |
    | (Future WAN Link)
    |
┌───┴────────────────────────────────────────────────┐
│         Router Namespace (Core L3)                  │
│  ┌──────────────────────────────────────────────┐  │
│  │         nftables Firewall Engine             │  │
│  │  - Stateful packet inspection                │  │
│  │  - Connection tracking                       │  │
│  │  - Zone-based rules                          │  │
│  │  - Logging & alerting                        │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  IP Forwarding: Enabled                            │
│  Routing Protocol: Static (OSPF capable via FRR)   │
└───┬────────────┬────────────┬────────────┬─────────┘
    │            │            │            │
    │            │            │            │
┌───┴──────┐ ┌──┴──────┐ ┌──┴──────┐ ┌──┴──────┐
│  VLAN 10 │ │ VLAN 20 │ │ VLAN 30 │ │ VLAN 40 │
│Management│ │   DMZ   │ │Internal │ │Database │
└────┬─────┘ └────┬────┘ └────┬────┘ └────┬────┘
     │            │            │            │
┌────▼────┐  ┌───▼────┐  ┌───▼────┐  ┌───▼────┐
│  mgmt   │  │  web   │  │  app   │  │   db   │
│ NS      │  │  NS    │  │  NS    │  │   NS   │
│.10      │  │ .10    │  │ .10    │  │  .10   │
└─────────┘  └────────┘  └────────┘  └────────┘
```

### Network Namespace Details

Each namespace represents an isolated network stack with its own:
- Routing table
- Network interfaces
- IP addresses
- Firewall rules (if configured)
- Processes and services

**Namespace Inventory:**

| Namespace | Type | Purpose | Services | Interfaces |
|-----------|------|---------|----------|------------|
| `router` | Infrastructure | L3 routing & firewall | nftables, FRR (optional) | 4 veth interfaces |
| `mgmt` | Management | Jump host, admin access | SSH (future), monitoring | 1 veth interface |
| `web` | DMZ | Public-facing web tier | Nginx web server | 1 veth interface |
| `app` | Internal | Application logic tier | Python HTTP server | 1 veth interface |
| `db` | Database | Data persistence tier | Python mock database | 1 veth interface |

### Virtual Ethernet (veth) Pairs

veth pairs act as virtual network cables, connecting namespaces:

```
router:veth-r-mgmt  <--->  mgmt:veth-mgmt-r   (VLAN 10)
router:veth-r-web   <--->  web:veth-web-r     (VLAN 20)
router:veth-r-app   <--->  app:veth-app-r     (VLAN 30)
router:veth-r-db    <--->  db:veth-db-r       (VLAN 40)
```

**Key Properties:**
- MTU: 1500 bytes (default)
- Speed: Virtual (not rate-limited by default)
- Duplex: Full duplex
- State: UP (administratively up)

---

## IP Addressing Scheme

### Address Space Design

**Chosen Block:** `10.10.0.0/16` (RFC 1918 private address space)

**Rationale:**
- Avoids conflicts with common home networks (192.168.x.x)
- Large enough for future expansion (65,534 hosts)
- Easy to remember and type during troubleshooting
- Follows enterprise conventions (10.x networks for internal)

### VLAN Subnet Allocation

| VLAN ID | Name       | Subnet         | Usable IPs    | Broadcast     | Hosts/VLAN |
|---------|------------|----------------|---------------|---------------|------------|
| 10      | Management | 10.10.10.0/24  | .1 - .254     | 10.10.10.255  | 254        |
| 20      | DMZ        | 10.10.20.0/24  | .1 - .254     | 10.10.20.255  | 254        |
| 30      | Internal   | 10.10.30.0/24  | .1 - .254     | 10.10.30.255  | 254        |
| 40      | Database   | 10.10.40.0/24  | .1 - .254     | 10.10.40.255  | 254        |

**Subnet Mask:** 255.255.255.0 (/24)  
**Network Size:** 256 addresses per VLAN  
**Usable Hosts:** 254 per VLAN (excluding network and broadcast)

### Host Addressing Convention

Each /24 subnet is divided into functional ranges:

```
10.10.X.0     - Network address (not usable)
10.10.X.1     - Default gateway (router interface)
10.10.X.2-9   - Reserved for network infrastructure (future switches, routers)
10.10.X.10-99 - Static server assignments
10.10.X.100-199 - DHCP pool (future dynamic assignment)
10.10.X.200-254 - Reserved for future use
10.10.X.255   - Broadcast address (not usable)
```

### Current IP Assignments

#### Router Namespace (Gateway IPs)

| Interface | IP Address | VLAN | Purpose |
|-----------|------------|------|---------|
| veth-r-mgmt | 10.10.10.1/24 | 10 | Management gateway |
| veth-r-web | 10.10.20.1/24 | 20 | DMZ gateway |
| veth-r-app | 10.10.30.1/24 | 30 | Internal gateway |
| veth-r-db | 10.10.40.1/24 | 40 | Database gateway |
| lo (loopback) | 127.0.0.1/8 | - | Loopback |

#### Host Namespaces

| Namespace | Interface | IP Address | Gateway | DNS (Future) |
|-----------|-----------|------------|---------|--------------|
| mgmt | veth-mgmt-r | 10.10.10.10/24 | 10.10.10.1 | 10.10.10.1 |
| web | veth-web-r | 10.10.20.10/24 | 10.10.20.1 | 10.10.10.1 |
| app | veth-app-r | 10.10.30.10/24 | 10.10.30.1 | 10.10.10.1 |
| db | veth-db-r | 10.10.40.10/24 | 10.10.40.1 | 10.10.10.1 |

### Routing Tables

Each host namespace has a simple routing table:

```bash
# Example: Management namespace routing table
10.10.10.0/24 dev veth-mgmt-r proto kernel scope link src 10.10.10.10
default via 10.10.10.1 dev veth-mgmt-r
```

Router namespace contains routes to all directly connected subnets:

```bash
# Router namespace routing table
10.10.10.0/24 dev veth-r-mgmt proto kernel scope link src 10.10.10.1
10.10.20.0/24 dev veth-r-web proto kernel scope link src 10.10.20.1
10.10.30.0/24 dev veth-r-app proto kernel scope link src 10.10.30.1
10.10.40.0/24 dev veth-r-db proto kernel scope link src 10.10.40.1
```

### DNS Strategy (Future Implementation)

**Current State:** No DNS, hosts use IP addresses

**Planned Implementation:**
```
10.10.10.1  - Primary DNS (dnsmasq on router)
10.10.10.2  - Secondary DNS (future redundancy)

Hostnames:
  mgmt.homelab.local  → 10.10.10.10
  web.homelab.local   → 10.10.20.10
  app.homelab.local   → 10.10.30.10
  db.homelab.local    → 10.10.40.10
```

---

## Security Architecture

### Security Zone Model

The network implements a **four-zone security architecture** based on trust levels and data sensitivity.

```
┌─────────────────────────────────────────────────────────┐
│                    Trust Boundaries                      │
│                                                          │
│   Highest ◄────────────────────────────────► Lowest    │
│                                                          │
│  Database   Internal      Management         DMZ        │
│  (VLAN 40)  (VLAN 30)     (VLAN 10)      (VLAN 20)     │
│                                                          │
│  Most        Protected     Full Access    Public        │
│  Restricted  Resources     To All        Facing         │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Zone Definitions

#### Zone 1: Management (VLAN 10)
**Trust Level:** (Highest - 5/5)

**Purpose:** Administrative access, monitoring, and management functions

**Characteristics:**
- Jump host for accessing other zones
- Future SSH bastion
- Monitoring and logging aggregation
- Network management tools

**Access Policy:**
- **Outbound:** Can access ALL zones (unrestricted)
- **Inbound:** SSH only from specific IP ranges (future)
- **Services:** SSH, monitoring agents, management tools

**Threat Model:**
- **Primary Risk:** Compromised admin credentials
- **Mitigation:** MFA, key-based auth, audit logging, time-based access

**Compliance Notes:** 
- PCI-DSS: Separate management network requirement
- SOC 2: Administrative access segregation

---

#### Zone 2: DMZ (VLAN 20)
**Trust Level:** (Low - 2/5)

**Purpose:** Public-facing web services, reverse proxies, load balancers

**Characteristics:**
- Internet-facing (simulated)
- High exposure to attacks
- No sensitive data storage
- Stateless applications preferred

**Access Policy:**
- **Outbound:** Can access Internal zone (VLAN 30) on **TCP port 8080 ONLY**
- **Inbound:** HTTP (80), HTTPS (443) from anywhere (future)
- **Blocked:** Direct access to Database zone
- **Services:** Nginx, Apache, HAProxy, static content

**Threat Model:**
- **Primary Risk:** Web application vulnerabilities, DDoS
- **Mitigation:** WAF, rate limiting, regular patching, minimal services
- **Assumption:** Treat as already compromised in design

**Design Rationale:**
- Even if web server is compromised, attacker cannot directly access database
- Limited outbound access prevents data exfiltration
- Stateful firewall tracks connections for return traffic

---

#### Zone 3: Internal (VLAN 30)
**Trust Level:** (High - 4/5)

**Purpose:** Application logic, business services, API servers

**Characteristics:**
- Not directly accessible from internet
- Houses business logic
- Can contain sensitive processing (but not storage)
- Stateful applications

**Access Policy:**
- **Outbound:** Can access Database zone (VLAN 40) on **TCP port 3306 ONLY**
- **Inbound:** TCP port 8080 from DMZ only
- **Blocked:** Outbound to DMZ, inbound from Database
- **Services:** Application servers, microservices, APIs

**Threat Model:**
- **Primary Risk:** SQL injection, business logic flaws
- **Mitigation:** Input validation, prepared statements, least privilege DB user
- **Defense:** Requires compromise of both DMZ AND application tier to reach data

**Design Rationale:**
- Separates presentation (DMZ) from business logic (Internal)
- Limits database access to only application tier
- Prevents DMZ from querying database directly

---

#### Zone 4: Database (VLAN 40)
**Trust Level:** (Highest - 5/5)

**Purpose:** Data persistence, sensitive data storage

**Characteristics:**
- Most sensitive data
- Most restricted access
- No outbound connectivity
- Highly monitored

**Access Policy:**
- **Outbound:** NONE (completely isolated)
- **Inbound:** TCP port 3306 from Internal zone ONLY
- **Blocked:** Everything else
- **Services:** MySQL, PostgreSQL, Redis, data stores

**Threat Model:**
- **Primary Risk:** Data breach, unauthorized access
- **Mitigation:** Network isolation, encryption at rest, limited accounts
- **Defense:** Requires compromise of all three tiers (DMZ, Internal, Database)

**Design Rationale:**
- No outbound prevents data exfiltration even if compromised
- Single access point (from application tier) simplifies auditing
- Follows principle of "data should never call out"

**Compliance Notes:**
- PCI-DSS: Cardholder data must be on isolated network
- HIPAA: PHI must have restricted access
- GDPR: Personal data must have access controls

---

### Firewall Rules (nftables)

#### Rule Processing Order

```
1. Check connection state (ESTABLISHED, RELATED) → ACCEPT
2. Check source IP against zone rules
3. If no explicit ALLOW → DROP (default policy)
4. Log dropped packets for analysis
```

#### Detailed Ruleset

```nft
table ip filter {
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Rule 1: Allow established/related connections (CRITICAL)
        # Allows return traffic for legitimate connections
        ct state established,related accept
        
        # Rule 2: Management zone - full access
        # Source: 10.10.10.0/24 (Management VLAN)
        # Destination: ANY
        # Rationale: Admins need access to all systems
        ip saddr 10.10.10.0/24 accept
        ip daddr 10.10.10.0/24 accept  # Allow inbound to management
        
        # Rule 3: DMZ → Internal (Web → App)
        # Source: 10.10.20.0/24 (DMZ)
        # Destination: 10.10.30.0/24 (Internal) on TCP 8080
        # Rationale: Web servers need to call application APIs
        # Note: ICMP is NOT allowed (ping will fail)
        ip saddr 10.10.20.0/24 \
        ip daddr 10.10.30.0/24 \
        tcp dport 8080 \
        ct state new accept
        
        # Rule 4: Internal → Database (App → DB)
        # Source: 10.10.30.0/24 (Internal)
        # Destination: 10.10.40.0/24 (Database) on TCP 3306
        # Rationale: Applications need to query database
        # Note: Only MySQL port, prevents other access
        ip saddr 10.10.30.0/24 \
        ip daddr 10.10.40.0/24 \
        tcp dport 3306 \
        ct state new accept
        
        # Rule 5: Logging rule (BEFORE final drop)
        # Logs all packets that don't match above rules
        # Useful for troubleshooting and security monitoring
        log prefix "[FIREWALL-DROP] " level info
        
        # Rule 6: Default drop (implicit via policy)
        # Everything not explicitly allowed is denied
        drop
    }
}
```

#### Blocked Traffic Examples

| Source | Destination | Port | Result | Reason |
|--------|-------------|------|--------|--------|
| DMZ | Database | 3306 | DROP | DMZ cannot directly access database |
| Internal | DMZ | 80 | DROP | Prevents reverse connections |
| Database | ANY | ANY | DROP | Database has no outbound access |
| DMZ | Internal | 22 | DROP | Only port 8080 allowed |
| Internet | Database | 3306 | DROP | Database not exposed externally |

#### Traffic Flow Examples

**Allowed Flow: Web → App → Database**
```
User Request:
  Browser → DMZ (10.10.20.10:80) → Internal (10.10.30.10:8080) → Database (10.10.40.10:3306)
  
Firewall Evaluation:
  1. DMZ → Internal on 8080: Rule 3 → ACCEPT
  2. Internal → Database on 3306: Rule 4 → ACCEPT
  3. Return traffic: Rule 1 (established) → ACCEPT
```

**Blocked Flow: DMZ → Database**
```
Attack Attempt:
  Compromised Web Server → Database (10.10.40.10:3306)
  
Firewall Evaluation:
  1. Check ct state: NEW connection
  2. Check Rule 3: Source matches DMZ, but destination is Database (not Internal)
  3. Check Rule 4: Source is DMZ (not Internal)
  4. No match found → Rule 5 (log) → Rule 6 (DROP)
  
Log Entry:
  [FIREWALL-DROP] IN=veth-r-web OUT=veth-r-db SRC=10.10.20.10 DST=10.10.40.10 PROTO=TCP DPT=3306
```

### Connection Tracking (Stateful Firewall)

The firewall maintains a connection tracking table:

```bash
# View active connections
sudo ip netns exec router cat /proc/net/nf_conntrack

# Example entry:
tcp 6 431999 ESTABLISHED src=10.10.20.10 dst=10.10.30.10 sport=54321 dport=8080 \
    src=10.10.30.10 dst=10.10.20.10 sport=8080 dport=54321 [ASSURED] mark=0
```

**Key States:**
- **NEW:** First packet of new connection
- **ESTABLISHED:** Connection is active, bidirectional traffic seen
- **RELATED:** Connection related to existing connection (e.g., FTP data channel)
- **INVALID:** Packet doesn't match any known connection

---

## Routing Design

### Routing Protocol Strategy

**Current Implementation:** Static routing (direct connect)

**Future Implementation:** OSPF via FRR (Free Range Routing)

### Static Routing (Current)

Each namespace has a default route pointing to its gateway:

```bash
# Management namespace
default via 10.10.10.1 dev veth-mgmt-r

# Web namespace
default via 10.10.20.1 dev veth-web-r

# App namespace
default via 10.10.30.1 dev veth-app-r

# Database namespace
default via 10.10.40.1 dev veth-db-r
```

Router namespace has directly connected routes only (no default gateway in current design).

### Dynamic Routing (Future - OSPF)

**Planned Configuration:**
```
Router ID: 10.10.10.1
Area: 0 (Backbone)
Networks:
  - 10.10.10.0/24 (Management)
  - 10.10.20.0/24 (DMZ)
  - 10.10.30.0/24 (Internal)
  - 10.10.40.0/24 (Database)
```

**Benefits:**
- Automatic failover if redundant paths added
- Easier to add new subnets
- Industry-standard protocol
- Foundation for multi-site connectivity

### Route Summarization

Current /24 subnets can be summarized as:
```
10.10.0.0/16 - Summary route for entire lab
10.10.10.0/22 - Summary for VLANs 10-13 (if expanded)
```

**Use Case:** Advertising lab networks to external router/VPN

---

## Service Architecture

### Service Inventory

| Service | Namespace | IP:Port | Protocol | Purpose |
|---------|-----------|---------|----------|---------|
| Nginx Web Server | web | 10.10.20.10:80 | HTTP | Frontend web server |
| Python HTTP (App) | app | 10.10.30.10:8080 | HTTP | Application backend |
| Python HTTP (DB Mock) | db | 10.10.40.10:3306 | HTTP | Mock database |
| FRR (Optional) | router | - | OSPF | Dynamic routing |

### Service Details

#### Web Service (Nginx)

**Configuration:** `~/homelab/configs/nginx-web.conf`

**Key Settings:**
```nginx
listen 10.10.20.10:80;  # Bind to specific IP
daemon off;             # Run in foreground (for namespace)
worker_processes auto;  # Scale with CPU cores
```

**Endpoints:**
- `GET /` - Returns server identification
- `GET /health` - Health check endpoint (returns "OK")

**Logs:**
- Access: `/tmp/nginx-web-access.log`
- Error: `/tmp/nginx-web-error.log`

**Future Enhancements:**
- TLS/SSL (port 443)
- Load balancing to multiple app servers
- Caching (proxy_cache)
- WAF integration (ModSecurity)

---

#### Application Service (Python HTTP Server)

**Implementation:** Custom Python HTTP server

**Key Features:**
```python
listen: 10.10.30.10:8080
handler: Simple GET responder
logging: Suppressed (redirect for production)
```

**Response:**
```
App Server (Internal)
VLAN: 30
IP: 10.10.30.10
```

**Future Enhancements:**
- Flask/Django application
- Database connection pooling
- Session management
- API gateway

---

#### Database Service (Mock)

**Implementation:** Python HTTP server (simulates database)

**Key Features:**
```python
listen: 10.10.40.10:3306  # Mimics MySQL port
protocol: HTTP (for simplicity)
authentication: None (lab only)
```

**Future Enhancements:**
- Actual MySQL/PostgreSQL
- Replication (primary/replica)
- Backup automation
- Encryption at rest

---

## Implementation Details

### Technology Stack

| Component | Technology | Purpose | Industry Equivalent |
|-----------|------------|---------|---------------------|
| Network Isolation | Linux Network Namespaces | Separate network stacks | VMs, Containers, VRFs |
| Virtual Links | veth pairs | Connect namespaces | Network cables, Trunk ports |
| Layer 3 Routing | iproute2 (`ip` command) | Routing & interfaces | Cisco IOS, JunOS |
| Firewall | nftables | Packet filtering & NAT | iptables, pf, Cisco ASA |
| Web Server | Nginx | HTTP server | Apache, IIS |
| Application | Python | Business logic | Node.js, Java, .NET |
| Routing Protocol | FRR (optional) | Dynamic routing | Quagga, BIRD, Cisco IOS |

### Namespace Creation Process

```bash
# Create namespace
ip netns add <name>

# What happens:
# 1. New network namespace created in /var/run/netns/
# 2. Isolated network stack instantiated
# 3. Loopback interface created (initially DOWN)
# 4. New routing table initialized (empty except localhost)
```

### veth Pair Creation

```bash
# Create veth pair
ip link add veth-a type veth peer name veth-b

# Move to namespaces
ip link set veth-a netns ns-a
ip link set veth-b netns ns-b

# What happens:
# 1. Kernel creates two interconnected virtual interfaces
# 2. Packets sent to one interface appear on the other
# 3. Interfaces moved to respective namespace network stacks
# 4. Isolation maintained (no cross-namespace visibility)
```

### IP Address Assignment

```bash
# Assign IP to interface in namespace
ip netns exec <namespace> ip addr add <IP>/<mask> dev <interface>

# What happens:
# 1. IP address bound to interface
# 2. Subnet route automatically added to routing table
# 3. Interface can now send/receive IP packets
# 4. ARP cache initialized for subnet
```

### Default Route Configuration

```bash
# Add default gateway
ip netns exec <namespace> ip route add default via <gateway>

# What happens:
# 1. Default route (0.0.0.0/0) added to routing table
# 2. All non-local traffic forwarded to gateway
# 3. Gateway must have route back (or return traffic fails)
```

---

## Scalability & Future Growth

### Capacity Planning

#### Current Capacity

| Resource | Current | Maximum (Design) | Notes |
|----------|---------|------------------|-------|
| Namespaces | 5 | ~1000 | Limited by system resources, not kernel |
| VLANs | 4 | 256 | Using /24 subnets from 10.10.0.0/16 |
| Hosts per VLAN | 1 | 254 | /24 subnet size limitation |
| veth Pairs | 4 | ~500 | Practical limit based on memory |
| Firewall Rules | 6 | ~10,000 | nftables can handle complex rulesets |
| Concurrent Connections | ~100 | ~10,000 | Limited by connection tracking table |

#### Horizontal Scaling Opportunities

**Add More Hosts to Existing VLANs:**
```bash
# Example: Add second web server
ip netns add web2
ip link add veth-r-web2 type veth peer name veth-web2-r
ip link set veth-r-web2 netns router
ip link set veth-web2-r netns web2
ip netns exec router ip addr add 10.10.20.2/24 dev veth-r-web2
ip netns exec web2 ip addr add 10.10.20.11/24 dev veth-web2-r
```

**Add New VLANs:**
```bash
# Example: Add Storage VLAN (VLAN 50)
VLAN 50 | Storage    | 10.10.50.0/24  | 10.10.50.1  | SAN, NAS, backup
```

**Vertical Scaling (Per Host):**
- Increase service worker processes
- Add resource limits (cgroups)
- Optimize application code
- Enable caching

#### Geographic Distribution

**Multi-Site Architecture:**
```
Site A (Lab 1)          Site B (Lab 2)
10.10.0.0/16    <-VPN-> 10.20.0.0/16
                  |
            WireGuard/IPSec
                  |
        Encrypted Tunnel
```

**Use Cases:**
- Disaster recovery simulation
- Multi-region deployments
- WAN optimization testing
- Site-to-site VPN practice

### High Availability Design

#### Redundant Router (Future)

```
        ┌────────────┐         ┌────────────┐
        │  Router 1  │         │  Router 2  │
        │ (Primary)  │◄───────►│ (Standby)  │
        │ VRRP Master│  VRRP   │VRRP Backup │
        └─────┬──────┘         └──────┬─────┘
              │                       │
              │     10.10.10.254      │
              │   (Virtual IP/VIP)    │
              │                       │
         ┌────┴───────────────────────┴────┐
         │        Shared VLAN Access       │
         └─────────────────────────────────┘
```

**Implementation:**
- VRRP (keepalived) for failover
- Shared VIP: 10.10.10.254
- Active-passive or active-active
- Sub-second failover time

#### Load Balancing

**Layer 4 Load Balancer (HAProxy):**
```
                    ┌──────────────┐
                    │   HAProxy    │
                    │ 10.10.20.50  │
                    └───────┬──────┘
                            │
            ┌───────────────┼───────────────┐
            │               │               │
      ┌─────▼────┐    ┌─────▼────┐   ┌─────▼────┐
      │  Web 1   │    │  Web 2   │   │  Web 3   │
      │10.10.20.10│   │10.10.20.11│  │10.10.20.12│
      └──────────┘    └──────────┘   └──────────┘
```

**Algorithms:**
- Round robin
- Least connections
- Source IP hash
- Health check based

### Performance Optimization

#### Tuning Parameters

**System-Level:**
```bash
# Increase connection tracking table size
sysctl -w net.netfilter.nf_conntrack_max=100000

# TCP tuning
sysctl -w net.ipv4.tcp_fin_timeout=30
sysctl -w net.ipv4.tcp_keepalive_time=300

# Buffer sizes
sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
```

**Namespace-Level:**
```bash
# In each namespace, adjust limits
ulimit -n 65536  # File descriptors
```

**Application-Level:**
- Nginx: worker_processes, worker_connections
- Python: Threading, async/await
- Connection pooling for database

#### Monitoring Points

**Key Metrics to Track:**
```
Network:
- Bandwidth utilization (RX/TX bytes)
- Packet drops/errors
- Connection count
- Firewall drops by rule

System:
- CPU usage per namespace
- Memory usage per namespace
- Open file descriptors
- Context switches

Application:
- Request latency (p50, p95, p99)
- Error rate
- Throughput (req/sec)
- Active connections
```

**Tools:**
- Prometheus + node_exporter
- Grafana dashboards
- ELK stack for logs
- Netdata for real-time

---

## Design Decisions & Trade-offs

### Decision Log

#### 1. Network Namespaces vs. VMs vs. Containers

**Decision:** Network namespaces

**Alternatives Considered:**
- **VMs (VirtualBox, KVM):** Full isolation, high overhead
- **Containers (Docker):** Good isolation, adds abstraction layer
- **Physical hardware:** Most realistic, expensive

**Rationale:**
- Lightweight (minimal overhead)
- Direct access to Linux networking
- Fast setup/teardown (< 30 seconds)
- No hypervisor needed
- Same tools as production systems
- Less isolation than VMs (same kernel)
- Requires root access

**Conclusion:** Best balance of realism, performance, and learning value for a lab environment.

---

#### 2. nftables vs. iptables

**Decision:** nftables

**Alternatives Considered:**
- **iptables:** Legacy, widely documented
- **firewalld:** Higher-level abstraction
- **pf (OpenBSD):** Different OS

**Rationale:**
- Modern replacement for iptables (RHEL 8+ default)
- Better performance (bytecode compilation)
- Cleaner syntax
- Single tool for all (instead of iptables/ip6tables/ebtables)
- Industry direction (new deployments use nft)
- Less documentation than iptables
- Syntax learning curve

**Conclusion:** Prepares students for modern infrastructure, aligns with RHEL/Rocky Linux defaults.

---

#### 3. Static Routing vs. Dynamic Routing

**Decision:** Static routing (with optional OSPF)

**Alternatives Considered:**
- **OSPF:** Industry standard, automatic failover
- **BGP:** Internet-scale routing
- **RIP:** Legacy protocol
- **EIGRP:** Cisco proprietary

**Rationale:**
- Simpler to understand initially
- No routing protocol overhead
- Sufficient for star topology
- Direct control over routes
- FRR available for easy OSPF addition
- No automatic failover
- Manual updates needed for changes

**Conclusion:** Start simple, add complexity as needed. OSPF remains option for advanced scenarios.

---

#### 4. /24 Subnets vs. Larger/Smaller

**Decision:** /24 (255.255.255.0)

**Alternatives Considered:**
- **/16:** 65,534 hosts (too large, hard to remember)
- **/25:** 126 hosts (too restrictive)
- **/23:** 510 hosts (non-standard, confusing)

**Rationale:**
- Standard enterprise subnet size
- Easy to calculate (254 hosts)
- Class C equivalent (familiar)
- Plenty of room for expansion
- Matches most documentation examples
- "Wastes" addresses in lab (only using 1-2 per subnet)

**Conclusion:** Industry convention, no reason to deviate for lab.

---

#### 5. Four Zones vs. Three vs. Five

**Decision:** Four zones (Management, DMZ, Internal, Database)

**Alternatives Considered:**
- **Three zones:** Combine Internal + Database
- **Five zones:** Add separate monitoring zone
- **Two zones:** Just DMZ + Internal

**Rationale:**
- Represents real enterprise architecture
- Demonstrates defense-in-depth
- Separates data tier (database) from logic tier (app)
- Management zone is best practice
- More complex than minimal setup
- More resources needed

**Conclusion:** Sweet spot between simplicity and realism. Teaches proper segmentation without overwhelming complexity.

---

#### 6. Nginx vs. Apache vs. Other

**Decision:** Nginx

**Alternatives Considered:**
- **Apache:** More features, heavier
- **HAProxy:** Load balancer focus
- **Lighttpd:** Very lightweight

**Rationale:**
- Industry standard for modern deployments
- Low resource usage
- Simple configuration
- Built into Rocky Linux repos
- Reverse proxy capabilities
- Slightly less documentation than Apache

**Conclusion:** Most relevant for current job market, efficient for lab.

---

#### 7. Mock Database vs. Real Database

**Decision:** Mock (Python HTTP server) initially, real database optional

**Alternatives Considered:**
- **MySQL:** Industry standard
- **PostgreSQL:** Advanced features
- **Redis:** In-memory, fast

**Rationale:**
- Simplifies initial setup (no database installation)
- Focuses on networking concepts, not database admin
- Faster lab build time
- Less resource usage
- Easy to swap for real database later
- Not realistic
- Can't practice SQL

**Conclusion:** Networking lab, not database lab. Real database available as extension.

---

### Known Limitations & Constraints

#### Architectural Limitations

1. **Single Point of Failure:**
   - Current: Only one router namespace
   - Impact: Router failure breaks entire network
   - Mitigation: Add redundant router with VRRP (Phase 2)

2. **No Internet Connectivity:**
   - Current: Isolated lab environment
   - Impact: Can't test real-world external access
   - Mitigation: Add NAT to host network (optional scenario)

3. **Same Kernel:**
   - Current: All namespaces share host kernel
   - Impact: Kernel exploit affects all namespaces
   - Mitigation: Accept for lab, use VMs for production

4. **No Layer 2 Simulation:**
   - Current: veth pairs are point-to-point
   - Impact: Can't simulate switches, broadcast domains
   - Mitigation: Use Linux bridge or Open vSwitch for L2 (Phase 3)

#### Performance Limitations

1. **CPU Bound:**
   - All namespaces compete for CPU
   - Heavy load on one affects others
   - Mitigation: cgroups for resource limits

2. **Memory Sharing:**
   - No hard memory limits by default
   - One namespace can exhaust system memory
   - Mitigation: Monitor usage, set cgroup limits

3. **No QoS:**
   - All traffic treated equally
   - Can't simulate bandwidth constraints
   - Mitigation: Add tc (traffic control) rules

4. **Connection Tracking Limits:**
   - Default nf_conntrack table size ~65k
   - High connection count scenarios limited
   - Mitigation: Increase sysctl limits

#### Security Limitations (Lab Only!)

1. **Weak Authentication:**
   - Services have no authentication
   - Acceptable for isolated lab
   - **NEVER do this in production**

2. **No Encryption:**
   - All traffic in plaintext
   - Easy to capture and analyze (good for learning)
   - Mitigation: Add TLS/SSL in Phase 2

3. **Root Required:**
   - Many commands need sudo/root
   - Security risk if scripts have bugs
   - Mitigation: Careful script review, rootless containers (future)

4. **No Audit Logging:**
   - Limited visibility into access/changes
   - Mitigation: Add syslog, audit daemon

---

## Appendix A: Quick Reference

### Network Summary Table

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Address Space** | 10.10.0.0/16 | Private RFC 1918 block |
| **Subnet Size** | /24 (255.255.255.0) | 254 usable hosts each |
| **VLANs** | 4 (10, 20, 30, 40) | Management, DMZ, Internal, DB |
| **Namespaces** | 5 | router, mgmt, web, app, db |
| **veth Pairs** | 4 | One per host namespace |
| **Firewall Rules** | 6 | Stateful, default deny |
| **Services** | 3 | Nginx, 2x Python HTTP |
| **Routing** | Static | Direct connect to router |

### IP Quick Reference

```
Router:    10.10.10.1, 10.10.20.1, 10.10.30.1, 10.10.40.1
Management: 10.10.10.10
Web (DMZ):  10.10.20.10
App:        10.10.30.10
Database:   10.10.40.10
```

### Port Reference

```
80    - HTTP (Nginx on web)
8080  - HTTP (Python on app)
3306  - Mock MySQL (Python on db)
```

### Common Commands

```bash
# List namespaces
ip netns list

# Enter namespace
sudo ip netns exec <ns> bash

# Check IPs
sudo ip netns exec <ns> ip addr

# Check routes
sudo ip netns exec <ns> ip route

# View firewall
sudo ip netns exec router nft list ruleset

# Test connectivity
sudo ip netns exec mgmt ping 10.10.20.10

# Packet capture
sudo ip netns exec router tcpdump -i veth-r-web

# Check services
ps aux | grep nginx
ps aux | grep python3
```

---

## Appendix B: Troubleshooting Decision Tree

```
Cannot ping between hosts?
│
├─> Check namespaces exist
│   └─> ip netns list
│
├─> Check interfaces are UP
│   └─> sudo ip netns exec <ns> ip link show
│
├─> Check IP addresses assigned
│   └─> sudo ip netns exec <ns> ip addr
│
├─> Check routing table
│   └─> sudo ip netns exec <ns> ip route
│
├─> Check IP forwarding on router
│   └─> sudo ip netns exec router sysctl net.ipv4.ip_forward
│
├─> Check firewall rules
│   └─> sudo ip netns exec router nft list ruleset
│
└─> Capture packets
    └─> sudo ip netns exec router tcpdump -i <interface> icmp
```

---

## Appendix C: Firewall Rule Testing Matrix

| Source | Dest | Port | Expected | Test Command |
|--------|------|------|----------|--------------|
| mgmt | web | 80 | ✅ PASS | `sudo ip netns exec mgmt curl 10.10.20.10` |
| mgmt | app | 8080 | ✅ PASS | `sudo ip netns exec mgmt curl 10.10.30.10:8080` |
| mgmt | db | 3306 | ✅ PASS | `sudo ip netns exec mgmt curl 10.10.40.10:3306` |
| web | app | 8080 | ✅ PASS | `sudo ip netns exec web curl 10.10.30.10:8080` |
| web | db | 3306 | ❌ BLOCK | `sudo ip netns exec web curl --max-time 3 10.10.40.10:3306` |
| app | db | 3306 | ✅ PASS | `sudo ip netns exec app curl 10.10.40.10:3306` |
| app | web | 80 | ❌ BLOCK | `sudo ip netns exec app curl --max-time 3 10.10.20.10` |
| db | * | * | ❌ BLOCK | `sudo ip netns exec db curl --max-time 3 10.10.20.10` |

---

## Appendix D: Expansion Ideas

### Short-Term (1-2 weeks)

1. **Add TLS/SSL** - Configure HTTPS on Nginx
2. **Real Database** - Install MySQL/PostgreSQL
3. **DNS Server** - Set up dnsmasq for name resolution
4. **Monitoring** - Add Prometheus + Grafana
5. **Logging** - Centralized syslog collection

### Medium-Term (1-2 months)

6. **Load Balancing** - HAProxy with multiple backends
7. **High Availability** - VRRP router failover
8. **Container Integration** - Docker with custom networks
9. **VPN Tunnel** - WireGuard site-to-site
10. **Ansible Automation** - Playbooks for setup

### Long-Term (3-6 months)

11. **Kubernetes** - Multi-node cluster simulation
12. **Service Mesh** - Istio or Linkerd
13. **SDN** - Open vSwitch with OpenFlow
14. **Security Tools** - Suricata IDS, WAF, SIEM
15. **CI/CD Pipeline** - GitLab CI for infrastructure testing

---

## Appendix E: Glossary

**Network Namespace:** Isolated network stack within Linux kernel. Separate interfaces, routing tables, and firewall rules.

**veth Pair:** Virtual Ethernet pair. Two interconnected virtual network interfaces that act like a virtual network cable.

**nftables:** Modern Linux firewall framework. Replaces iptables with improved performance and cleaner syntax.

**Security Zone:** Network segment with defined trust level and access policies. Implements defense-in-depth strategy.

**Stateful Firewall:** Firewall that tracks connection state. Allows return traffic automatically for established connections.

**Default Deny:** Security policy where everything is blocked unless explicitly allowed. Opposite of default allow.

**DMZ (Demilitarized Zone):** Network segment for public-facing services. Isolated from internal network for security.

**Jump Host:** Secure access point for managing internal systems. Also called bastion host.

**Connection Tracking (conntrack):** Kernel subsystem that tracks network connections for stateful firewalls and NAT.

**VLAN:** Virtual Local Area Network. Logical network segmentation on physical infrastructure.

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2024 | Network Team | Initial comprehensive design documentation |

---

## References

1. **Linux Network Namespaces**
   - https://man7.org/linux/man-pages/man7/network_namespaces.7.html
   - Kernel documentation

2. **nftables**
   - https://wiki.nftables.org/
   - Official nftables wiki

3. **RHEL 8/9 Networking Guide**
   - https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/
   - Red Hat official documentation

4. **RFC 1918 - Private Address Space**
   - https://tools.ietf.org/html/rfc1918
   - Private IP address allocation

5. **PCI-DSS Requirements**
   - Network segmentation requirements for payment card data

6. **NIST Cybersecurity Framework**
   - Network security best practices

---

**END OF DOCUMENT**

*This design document is a living document and should be updated as the network evolves.*