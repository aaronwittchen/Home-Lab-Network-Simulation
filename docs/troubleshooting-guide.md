# Network Design Documentation
---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Design Goals](#design-goals)
3. [Network Topology](#network-topology)
4. [IP Addressing Scheme](#ip-addressing-scheme)
5. [Security Architecture](#security-architecture)
6. [Routing Design](#routing-design)
7. [Service Architecture](#service-architecture)
8. [Implementation Technology](#implementation-technology)
9. [Scalability Considerations](#scalability-considerations)
10. [Future Enhancements](#future-enhancements)

---

## Executive Summary

This document describes the network architecture for a multi-tier datacenter simulation built using Linux network namespaces on Rocky Linux. The design implements industry-standard security zones, defense-in-depth strategies, and scalable service architecture patterns commonly found in enterprise datacenters.

**Key Characteristics:**
- **4 Security Zones** with distinct trust levels
- **Stateful firewall** with default-deny policy
- **Service isolation** using network segmentation
- **Defense in depth** with multiple security layers
- **Zero-trust principles** between zones

**Target Use Cases:**
- Network engineering skill development
- Security architecture learning
- Service deployment practices
- Troubleshooting and diagnostics training
- Certification preparation (RHCSA, RHCE, CCNA)

---

## Design Goals

### Primary Objectives

1. **Simulate Real Datacenter Architecture**
   - Multi-tier application deployment (Web → App → DB)
   - Security zone segmentation (Management, DMZ, Internal, Database)
   - Defense in depth with firewall controls
   - Service isolation and least privilege access

2. **Educational Value**
   - Learn real networking concepts without expensive hardware
   - Practice production troubleshooting scenarios
   - Understand security best practices
   - Gain hands-on experience with enterprise tools

3. **Production-Like Patterns**
   - Modular, maintainable design
   - Automated deployment and teardown
   - Comprehensive testing and monitoring
   - Clear documentation and runbooks

4. **Lightweight & Portable**
   - Run on single VM or physical host
   - Quick setup/teardown (< 1 minute)
   - Minimal resource consumption
   - Easy to extend and customize

### Non-Goals

- ❌ High-performance production deployment
- ❌ Physical hardware simulation
- ❌ Full enterprise feature parity
- ❌ Multi-host distributed networking (initially)

---

## Network Topology

### High-Level Architecture

```
                         ┌─────────────────────┐
                         │   Physical Host     │
                         │   Rocky Linux VM    │
                         │                     │
                         │  ┌───────────────┐  │
                         │  │   Router NS   │  │
                         │  │  (Gateway)    │  │
                         │  └───────┬───────┘  │
                         │          │          │
                         │  ┌───────┴───────┐  │
                         │  │   Bridge/FW   │  │
                         │  │   nftables    │  │
                         │  └───┬───┬───┬───┘  │
                         │      │   │   │      │
        ┌────────────────┼──────┘   │   └──────┼────────────────┐
        │                │          │          │                │
        │                │          │          │                │
   ┌────▼─────┐    ┌────▼─────┐  ┌─▼────┐  ┌──▼──────┐         │
   │  Mgmt NS │    │  Web NS  │  │ App  │  │  DB NS  │         │
   │  VLAN 10 │    │  VLAN 20 │  │ NS   │  │ VLAN 40 │         │
   │          │    │   (DMZ)  │  │VLAN  │  │         │         │
   │  Jump    │    │          │  │ 30   │  │         │         │
   │  Host    │    │  Nginx   │  │      │  │  Mock   │         │
   │          │    │  :80     │  │:8080 │  │  DB     │         │
   └──────────┘    └──────────┘  └──────┘  │ :3306   │         │
                                            └─────────┘         │
                         │                                      │
                         └──────────────────────────────────────┘
```

### Detailed Layer-2/3 Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                         Router Namespace                         │
│                       (Central Gateway)                          │
│                                                                  │
│  veth-r-mgmt      veth-r-web      veth-r-app      veth-r-db    │
│  10.10.10.1/24    10.10.20.1/24   10.10.30.1/24   10.10.40.1/24│
│      │                │                │               │        │
└──────┼────────────────┼────────────────┼───────────────┼────────┘
       │                │                │               │
       │ veth pair      │ veth pair      │ veth pair     │ veth pair
       │                │                │               │
┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐  ┌────▼────────┐
│   Mgmt NS   │  │   Web NS    │  │   App NS    │  │   DB NS     │
│             │  │             │  │             │  │             │
│veth-mgmt-r  │  │veth-web-r   │  │veth-app-r   │  │veth-db-r    │
│10.10.10.10  │  │10.10.20.10  │  │10.10.30.10  │  │10.10.40.10  │
│    /24      │  │    /24      │  │    /24      │  │    /24      │
│             │  │             │  │             │  │             │
│ Gateway:    │  │ Gateway:    │  │ Gateway:    │  │ Gateway:    │
│ 10.10.10.1  │  │ 10.10.20.1  │  │ 10.10.30.1  │  │ 10.10.40.1  │
└─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘

Legend:
  NS = Network Namespace (isolated network stack)
  veth pair = Virtual Ethernet cable (bidirectional link)
```

### Virtual Ethernet (veth) Pair Details

Each veth pair creates a bidirectional virtual "cable" connecting two network namespaces:

| Link Name | Side A (Router) | Side B (Host NS) | Purpose |
|-----------|----------------|------------------|---------|
| Link 1 | veth-r-mgmt | veth-mgmt-r | Router ↔ Management |
| Link 2 | veth-r-web | veth-web-r | Router ↔ Web (DMZ) |
| Link 3 | veth-r-app | veth-app-r | Router ↔ App (Internal) |
| Link 4 | veth-r-db | veth-db-r | Router ↔ Database |

**Why veth pairs?**
- Acts like physical ethernet cable connecting two devices
- No need for actual physical NICs or switches
- Full Layer-2 and Layer-3 functionality
- Used by Docker, Kubernetes, and other container systems

---

## IP Addressing Scheme

### Subnet Allocation

| VLAN | Zone | Network | Broadcast | Usable Range | Hosts | Gateway | Purpose |
|------|------|---------|-----------|--------------|-------|---------|---------|
| 10 | Management | 10.10.10.0/24 | 10.10.10.255 | 10.10.10.1 - 254 | 254 | 10.10.10.1 | Admin/Jump hosts, monitoring |
| 20 | DMZ | 10.10.20.0/24 | 10.10.20.255 | 10.10.20.1 - 254 | 254 | 10.10.20.1 | Public-facing web servers |
| 30 | Internal | 10.10.30.0/24 | 10.10.30.255 | 10.10.30.1 - 254 | 254 | 10.10.30.1 | Application servers |
| 40 | Database | 10.10.40.0/24 | 10.10.40.255 | 10.10.40.1 - 254 | 254 | 10.10.40.1 | Database servers |

**Total Address Space:** 1,016 usable IPs (4 × 254)

### Host Allocation Strategy

Each /24 subnet is divided into functional blocks:

```
.1          = Gateway (router interface)
.2 - .9     = Reserved for network infrastructure (future switches, routers)
.10 - .99   = Static server assignments
.100 - .199 = DHCP pool (future dynamic allocation)
.200 - .254 = Reserved for future expansion
```

### Current Host Assignments

| Hostname | FQDN (future) | IP Address | Interface | Zone | Role |
|----------|---------------|------------|-----------|------|------|
| router | router.lab.local | 10.10.10.1 | veth-r-mgmt | N/A | Gateway |
| router | router.lab.local | 10.10.20.1 | veth-r-web | N/A | Gateway |
| router | router.lab.local | 10.10.30.1 | veth-r-app | N/A | Gateway |
| router | router.lab.local | 10.10.40.1 | veth-r-db | N/A | Gateway |
| mgmt01 | mgmt01.lab.local | 10.10.10.10 | veth-mgmt-r | Management | Jump host |
| web01 | web01.lab.local | 10.10.20.10 | veth-web-r | DMZ | Web server |
| app01 | app01.lab.local | 10.10.30.10 | veth-app-r | Internal | App server |
| db01 | db01.lab.local | 10.10.40.10 | veth-db-r | Database | DB server |

### Routing Tables

**Router Namespace:**
```
Destination     Gateway         Interface       Metric
10.10.10.0/24   0.0.0.0         veth-r-mgmt     0      (directly connected)
10.10.20.0/24   0.0.0.0         veth-r-web      0      (directly connected)
10.10.30.0/24   0.0.0.0         veth-r-app      0      (directly connected)
10.10.40.0/24   0.0.0.0         veth-r-db       0      (directly connected)
```

**Host Namespaces (Example: Management):**
```
Destination     Gateway         Interface       Metric
10.10.10.0/24   0.0.0.0         veth-mgmt-r     0      (local subnet)
0.0.0.0/0       10.10.10.1      veth-mgmt-r     0      (default via router)
```

---

## Security Architecture

### Security Zones (Trust Levels)

```
┌────────────────────────────────────────────────────────────┐
│                    TRUST LEVEL HIERARCHY                    │
├────────────────────────────────────────────────────────────┤
│                                                             │
│  HIGHEST ─┐                                                 │
│           │  ┌─────────────────────────────────────┐       │
│           ├──│  Management Zone (VLAN 10)          │       │
│           │  │  • Jump hosts, admin workstations   │       │
│           │  │  • Monitoring systems               │       │
│           │  │  • Full access to all zones         │       │
│           │  └─────────────────────────────────────┘       │
│           │                                                 │
│  HIGH ────┤  ┌─────────────────────────────────────┐       │
│           ├──│  Database Zone (VLAN 40)            │       │
│           │  │  • Database servers                 │       │
│           │  │  • Highly protected data            │       │
│           │  │  • No outbound access               │       │
│           │  └─────────────────────────────────────┘       │
│           │                                                 │
│  MEDIUM ──┤  ┌─────────────────────────────────────┐       │
│           ├──│  Internal Zone (VLAN 30)            │       │
│           │  │  • Application servers              │       │
│           │  │  • Backend services                 │       │
│           │  │  • Limited database access          │       │
│           │  └─────────────────────────────────────┘       │
│           │                                                 │
│  LOW ─────┘  ┌─────────────────────────────────────┐       │
│              │  DMZ Zone (VLAN 20)                 │       │
│              │  • Public-facing web servers        │       │
│              │  • Exposed to internet traffic      │       │
│              │  • Limited internal access          │       │
│              └─────────────────────────────────────┘       │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

### Defense in Depth Strategy

**Layer 1: Network Segmentation**
- VLANs isolate different security zones
- Separate subnets prevent direct Layer-2 communication
- All inter-zone traffic must traverse router/firewall

**Layer 2: Stateful Firewall**
- Default-deny policy (implicit drop)
- Explicit allow rules for required traffic only
- Connection state tracking (established/related)
- Logging of denied traffic

**Layer 3: Service Isolation**
- Each service runs in isolated namespace
- Minimal services exposed per host
- Port-based access control

**Layer 4: Least Privilege Access**
- Only necessary ports opened
- Directional traffic rules (source → destination)
- No unnecessary bidirectional access

### Firewall Ruleset Design

#### Policy Philosophy

```
1. Default Deny All Traffic
2. Allow Management → Everywhere (admin access)
3. Allow Established/Related Connections (stateful)
4. Allow Specific Service Flows Only
5. Log Everything Denied
```

#### Detailed Firewall Rules

```nft
table ip filter {
    chain forward {
        type filter hook forward priority 0; policy drop;
        
        # Rule 1: Allow established/related connections (stateful)
        ct state established,related accept
        
        # Rule 2: Management zone can access everything
        ip saddr 10.10.10.0/24 accept
        ip daddr 10.10.10.0/24 accept
        
        # Rule 3: DMZ → Internal (Web → App)
        ip saddr 10.10.20.0/24 ip daddr 10.10.30.0/24 \
            tcp dport 8080 ct state new accept
        
        # Rule 4: Internal → Database (App → DB)
        ip saddr 10.10.30.0/24 ip daddr 10.10.40.0/24 \
            tcp dport 3306 ct state new accept
        
        # Rule 5: Log and drop everything else
        log prefix "[FIREWALL-DROP] " level info drop
    }
}
```

#### Traffic Flow Matrix

| Source Zone | Destination Zone | Allowed Protocols | Ports | Action |
|-------------|------------------|-------------------|-------|--------|
| Management | DMZ | ALL | ALL | ✅ ACCEPT |
| Management | Internal | ALL | ALL | ✅ ACCEPT |
| Management | Database | ALL | ALL | ✅ ACCEPT |
| DMZ | Internal | TCP | 8080 | ✅ ACCEPT |
| DMZ | Database | ALL | ALL | ❌ DROP |
| DMZ | Management | ALL | ALL | ❌ DROP |
| Internal | Database | TCP | 3306 | ✅ ACCEPT |
| Internal | DMZ | ALL | ALL | ❌ DROP |
| Internal | Management | ALL | ALL | ❌ DROP |
| Database | DMZ | ALL | ALL | ❌ DROP |
| Database | Internal | ALL | ALL | ❌ DROP |
| Database | Management | ALL | ALL | ❌ DROP |

### Security Zone Details

#### 1. Management Zone (VLAN 10)

**Purpose:** Administrative access and monitoring

**Trust Level:** HIGHEST

**Allowed Inbound:**
- SSH from specific admin IPs (future: bastion host)
- Monitoring queries (future: Prometheus scrapes)

**Allowed Outbound:**
- Full access to all zones (administrative needs)
- Internet access (for updates, package installation)

**Hosts:**
- Jump/Bastion hosts
- Monitoring systems (Prometheus, Grafana)
- Log aggregation servers
- Configuration management systems

**Best Practices:**
- Multi-factor authentication for SSH
- SSH key-based authentication only
- Audit logging of all admin actions
- Time-based access controls
- Regular access reviews

#### 2. DMZ Zone (VLAN 20)

**Purpose:** Public-facing services

**Trust Level:** LOW (untrusted/semi-trusted)

**Allowed Inbound:**
- HTTP/HTTPS from anywhere (ports 80, 443)
- Health checks from load balancer

**Allowed Outbound:**
- TCP 8080 to Internal zone (app tier) only
- NO direct database access
- NO lateral movement within DMZ

**Hosts:**
- Web servers (Nginx, Apache)
- Load balancers (HAProxy)
- Reverse proxies
- API gateways

**Security Considerations:**
- Assume compromise (exposed to internet)
- Minimal sensitive data stored
- Read-only application code
- Regular security scanning
- WAF (Web Application Firewall) integration

#### 3. Internal Zone (VLAN 30)

**Purpose:** Application logic and business services

**Trust Level:** MEDIUM

**Allowed Inbound:**
- TCP 8080 from DMZ zone only
- Management access from VLAN 10

**Allowed Outbound:**
- TCP 3306 to Database zone only
- NO DMZ access (prevent reverse shell attacks)
- API calls to external services (future)

**Hosts:**
- Application servers (Python, Node.js, Java)
- Message queues (RabbitMQ, Kafka)
- Cache servers (Redis, Memcached)
- Background job processors

**Security Considerations:**
- Service account with minimal DB privileges
- No direct internet access
- Encrypted connections to database
- Application-level authentication
- Input validation and sanitization

#### 4. Database Zone (VLAN 40)

**Purpose:** Data persistence and storage

**Trust Level:** HIGHEST (most protected)

**Allowed Inbound:**
- TCP 3306 from Internal zone only
- Management access from VLAN 10
- Backup connections (future)

**Allowed Outbound:**
- NONE (no outbound connections)
- Backup replication (future)

**Hosts:**
- Database servers (MySQL, PostgreSQL, MariaDB)
- Database replicas (read replicas)
- Backup servers

**Security Considerations:**
- Encrypted at rest (future)
- Encrypted in transit (TLS)
- Strong authentication required
- Regular backups to separate network
- No direct internet access
- Minimal exposed services

---

## Routing Design

### Current Implementation: Static Routes

**Advantages:**
- Simple and predictable
- Low overhead
- No routing protocol complexity
- Suitable for small, stable topologies

**Configuration:**
All subnets are directly connected to the router namespace, requiring no additional static routes beyond the directly connected networks.

### Future Enhancement: Dynamic Routing (OSPF)

**When to implement:**
- Multiple routers added
- Redundant paths needed
- Automatic failover required
- Network grows beyond simple star topology

**OSPF Design (Future):**

```
Area 0 (Backbone)
├── 10.10.10.0/24 (Management)
├── 10.10.20.0/24 (DMZ)
├── 10.10.30.0/24 (Internal)
└── 10.10.40.0/24 (Database)

Router ID: 10.10.10.1
Cost Metric: Based on interface bandwidth
```

**FRR Configuration Example:**
```
router ospf
  ospf router-id 10.10.10.1
  network 10.10.10.0/24 area 0
  network 10.10.20.0/24 area 0
  network 10.10.30.0/24 area 0
  network 10.10.40.0/24 area 0
```

---

## Service Architecture

### Three-Tier Application Design

```
┌─────────────────────────────────────────────────────────┐
│                   CLIENT REQUEST                         │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  PRESENTATION TIER (DMZ - VLAN 20)                      │
│                                                          │
│  ┌────────────────────────────────────────┐             │
│  │  Web Server (Nginx)                    │             │
│  │  - Serves static content               │             │
│  │  - SSL/TLS termination                 │             │
│  │  - Reverse proxy to app tier           │             │
│  │  - Rate limiting                       │             │
│  │  Port: 80/443                          │             │
│  └────────────────────────────────────────┘             │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP :8080
                         ▼
┌─────────────────────────────────────────────────────────┐
│  APPLICATION TIER (Internal - VLAN 30)                  │
│                                                          │
│  ┌────────────────────────────────────────┐             │
│  │  App Server (Python/Node.js)           │             │
│  │  - Business logic                      │             │
│  │  - API endpoints                       │             │
│  │  - Session management                  │             │
│  │  - Authentication/Authorization        │             │
│  │  Port: 8080                            │             │
│  └────────────────────────────────────────┘             │
└────────────────────────┬────────────────────────────────┘
                         │ MySQL :3306
                         ▼
┌─────────────────────────────────────────────────────────┐
│  DATA TIER (Database - VLAN 40)                         │
│                                                          │
│  ┌────────────────────────────────────────┐             │
│  │  Database Server (MariaDB/PostgreSQL)  │             │
│  │  - Data persistence                    │             │
│  │  - ACID transactions                   │             │
│  │  - Query processing                    │             │
│  │  - Replication (future)                │             │
│  │  Port: 3306                            │             │
│  └────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────┘
```

### Service Communication Flow

```
1. Client → Web Server (DMZ)
   Protocol: HTTP/HTTPS
   Port: 80/443
   Description: User accesses web application

2. Web Server → App Server (Internal)
   Protocol: HTTP
   Port: 8080
   Firewall Rule: DMZ → Internal, TCP 8080
   Description: Web tier proxies to app tier

3. App Server → Database Server
   Protocol: MySQL
   Port: 3306
   Firewall Rule: Internal → Database, TCP 3306
   Description: App tier queries database

4. Management → All Tiers
   Protocol: SSH, HTTP (monitoring)
   Ports: 22, various
   Firewall Rule: Management → All zones
   Description: Admin access and monitoring
```

---

## Implementation Technology

### Core Technologies

| Technology | Purpose | Production Equivalent |
|------------|---------|----------------------|
| **Network Namespaces** | Network isolation | VMs, containers, VRFs |
| **veth Pairs** | Virtual links | Physical ethernet, VLANs |
| **nftables** | Stateful firewall | Palo Alto, Cisco ASA, iptables |
| **iproute2** | Network configuration | Cisco IOS commands |
| **Nginx** | Web server | Production web servers |
| **Python HTTP** | Mock services | Real application servers |
| **Bash Scripts** | Automation | Ansible, Terraform |

### Network Namespace Architecture

**What are Network Namespaces?**

Network namespaces provide isolated network stacks within a single Linux kernel:

```
┌──────────────────────────────────────────────────────┐
│              Linux Kernel                             │
│                                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ netns 1  │  │ netns 2  │  │ netns 3  │          │
│  │          │  │          │  │          │          │
│  │ • Routes │  │ • Routes │  │ • Routes │          │
│  │ • IPs    │  │ • IPs    │  │ • IPs    │          │
│  │ • FW     │  │ • FW     │  │ • FW     │          │
│  │ • IF     │  │ • IF     │  │ • IF     │          │
│  └──────────┘  └──────────┘  └──────────┘          │
│                                                       │
└──────────────────────────────────────────────────────┘

Each namespace has its own:
  - Network interfaces
  - IP addresses
  - Routing tables
  - Firewall rules
  - Network statistics
```

**Why Namespaces for This Project?**

✅ **Lightweight:** No VM overhead, instant creation  
✅ **Realistic:** Same kernel networking as production  
✅ **Educational:** Learn real Linux networking  
✅ **Practical:** Used by Docker, Kubernetes, containers  
✅ **Flexible:** Easy to create/destroy for experiments  

### nftables Firewall

**Why nftables over iptables?**

| Feature | nftables | iptables (legacy) |
|---------|----------|-------------------|
| Syntax | Cleaner, more readable | Complex, verbose |
| Performance | Better (single kernel framework) | Multiple subsystems |
| IPv4/IPv6 | Unified | Separate commands |
| Updates | Active development | Maintenance mode |
| RHEL 8+ | Default | Available but deprecated |

**nftables Architecture:**

```
nftables Structure:
  table
    └── chain
          └── rule
                └── action

Example:
  table ip filter
    └── chain forward
          ├── rule: accept established
          ├── rule: accept management
          ├── rule: accept dmz→app:8080
          └── rule: drop all
```

---

## Scalability Considerations

### Current Limitations

**Single Host:**
- All namespaces on one VM
- Limited by host resources
- No true geographic distribution

**Static Configuration:**
- Manual IP assignment
- No DHCP
- No DNS resolution

**Simple Topology:**
- Star topology (all through central router)
- Single point of failure
- No redundancy

### Horizontal Scaling Plan

#### Phase 1: Add Redundancy (Same Host)

**Add Multiple Web/App Servers:**
```
Before:                    After:
┌──────┐                   ┌───────┐  ┌───────┐
│ web  │                   │ web01 │  │ web02 │
└──────┘                   └───────┘  └───────┘
                           10.10.20.10  10.10.20.11

┌──────┐                   ┌───────┐  ┌───────┐
│ app  │                   │ app01 │  │ app02 │
└──────┘                   └───────┘  └───────┘
                           10.10.30.10  10.10.30.11
```

**Add Load Balancer:**
```
                ┌─────────────────┐
                │  Load Balancer  │
                │   10.10.20.5    │
                └────────┬────────┘
                         │
            ┌────────────┴────────────┐
            │                         │
       ┌────▼────┐               ┌────▼────┐
       │ web01   │               │ web02   │
       │10.10.20.10│             │10.10.20.11│
       └─────────┘               └─────────┘
```

#### Phase 2: Add High Availability

**Dual Router Design:**
```
        ┌─────────┐         ┌─────────┐
        │ router1 │◄───────►│ router2 │
        │ VRRP    │  VRRP   │ VRRP    │
        │ Master  │         │ Backup  │
        └────┬────┘         └────┬────┘
             │                   │
        VIP: 10.10.10.1 (floating)
```

#### Phase 3: Multi-Host Distribution

**Extend Across Physical Hosts:**
```
Host 1 (Rocky VM)           Host 2 (Rocky VM)
┌─────────────────┐         ┌─────────────────┐
│  web01, app01   │◄───────►│  web02, app02   │
│  router1        │ VXLAN   │  router2        │
└─────────────────┘         └─────────────────┘
```

### Vertical Scaling Considerations

**Resource Limits per Namespace:**
```bash
# CPU limits (cgroups)
cgcreate -g cpu:/web
cgset -r cpu.shares=512 web
cgclassify -g cpu:web <pid>

# Memory limits
cgcreate -g memory:/web
cgset -r memory.limit_in_bytes=512M web
```

---

## Future Enhancements

### Phase 1: Core Improvements (Next 1-2 months)

1. **DNS Resolution**
   - Deploy BIND9 or dnsmasq in management zone
   - Create forward/reverse zones
   - Implement split-horizon DNS
   - Use hostnames instead of IPs

2. **DHCP Service**
   - Configure ISC DHCP in each VLAN
   - Dynamic IP assignment (.100-.199 range)
   - Option 66/67 for PXE boot

3. **Load Balancing**
   - Deploy HAProxy in DMZ
   - Round-robin to multiple web servers
   - Health checks and automatic failover
   - Session persistence

### Phase 2: Monitoring & Observability (Months 2-3)

4. **Metrics Collection**
   - Prometheus exporters in each namespace
   - Node exporter for system metrics
   - Custom app metrics
   - Grafana dashboards

5. **Centralized Logging**
   - ELK stack or Loki deployment
   - Rsyslog forwarding from all hosts
   - Log retention policies
   - Alert rules for critical events

6. **Alerting System**
   - AlertManager for Prometheus
   - PagerDuty/Slack integration
   - Threshold-based alerts
   - Anomaly detection

### Phase 3: Security Enhancements (Months 3-4)

7. **VPN & Encryption**
   - WireGuard VPN between sites
   - TLS/SSL for all services
   - Certificate management (Let's Encrypt)
   - IPSec for sensitive traffic

8. **Intrusion Detection**
   - Suricata or Snort deployment
   - Network-based IDS
   - Signature updates
   - Alert correlation

9. **Security Hardening**
   - SELinux policy enforcement
   - Fail2ban for brute force protection
   - OSSEC for host-based IDS
   - Regular vulnerability scanning

10. **Secrets Management**
    - HashiCorp Vault deployment
    - Dynamic secrets for databases
    - PKI for certificate management
    - Encrypted storage

### Phase 4: Automation & Orchestration (Months 4-6)

11. **Infrastructure as Code**
    - Convert to Ansible playbooks
    - Terraform for infrastructure
    - GitOps workflow
    - Automated testing pipeline

12. **Configuration Management**
    - Puppet or SaltStack
    - Centralized config repository
    - Change tracking
    - Rollback capabilities

13. **CI/CD Pipeline**
    - GitLab CI or Jenkins
    - Automated testing
    - Canary deployments
    - Blue-green deployment strategy

### Phase 5: Advanced Topics (Months 6+)

14. **Container Integration**
    - Docker in namespaces
    - Kubernetes cluster setup
    - Calico/Cilium networking
    - Service mesh (Istio basics)

15. **Software Defined Networking**
    - Open vSwitch deployment
    - VXLAN overlays
    - Network virtualization
    - Centralized SDN controller

16. **Multi-Region Architecture**
    - Geographic distribution
    - Cross-site replication
    - Global load balancing
    - Disaster recovery

17. **Performance Optimization**
    - Network tuning (TCP parameters)
    - Jumbo frames (if supported)
    - NIC offloading
    - Latency optimization

18. **Compliance & Audit**
    - CIS benchmarks implementation
    - Compliance scanning (OpenSCAP)
    - Audit logging (auditd)
    - Regular security assessments

---

## Design Decisions & Rationale

### Why Network Namespaces?

**Decision:** Use Linux network namespaces instead of VMs or containers

**Rationale:**
- ✅ Lightweight (minimal resource overhead)
- ✅ Fast creation/destruction (< 1 second)
- ✅ Real Linux networking stack (authentic learning)
- ✅ Industry relevance (Docker, Kubernetes use namespaces)
- ✅ No hypervisor required
- ✅ Easy to experiment and break things

**Alternatives Considered:**
- ❌ **VMs:** Too heavy, slow, resource-intensive
- ❌ **Docker containers:** Abstracts too much, less educational
- ❌ **GNS3/EVE-NG:** Great for Cisco but not Linux-focused

### Why nftables over iptables?

**Decision:** Use nftables for firewall implementation

**Rationale:**
- ✅ Default in RHEL 8+ (Rocky Linux 8/9)
- ✅ Cleaner syntax, easier to understand
- ✅ Better performance
- ✅ Unified IPv4/IPv6 handling
- ✅ Active development and future-proof
- ✅ Industry moving toward nftables

**Migration Path:**
- Still document iptables equivalents for reference
- Provide translation guide for legacy systems

### Why /24 Subnets?

**Decision:** Use /24 (255 hosts) for each VLAN

**Rationale:**
- ✅ Simple CIDR calculation (easy to understand)
- ✅ Room for growth (254 hosts per VLAN)
- ✅ Matches common enterprise practices
- ✅ Easy subnetting for beginners
- ✅ Plenty of space for expansion

**Alternatives Considered:**
- ❌ **/25 or /26:** Too small, limits learning scenarios
- ❌ **/16:** Too large, overkill for lab environment
- ✅ **/24 is the "Goldilocks" size**

### Why 10.10.x.x Addressing?

**Decision:** Use 10.10.0.0/16 private address space

**Rationale:**
- ✅ RFC 1918 private addressing
- ✅ Won't conflict with home networks (usually 192.168.x.x)
- ✅ Easy to remember pattern (10.10.VLAN.HOST)
- ✅ Room for 256 VLANs (we use 4)
- ✅ Clear visual separation (VLAN number in 3rd octet)

**Pattern:**
```
10.10.10.x = VLAN 10 (Management)
10.10.20.x = VLAN 20 (DMZ)
10.10.30.x = VLAN 30 (Internal)
10.10.40.x = VLAN 40 (Database)
```

### Why Star Topology?

**Decision:** Central router with star topology

**Rationale:**
- ✅ Simplest to understand for beginners
- ✅ Mimics traditional datacenter design
- ✅ Clear traffic flow patterns
- ✅ Easy to troubleshoot
- ✅ Natural firewall chokepoint
- ✅ Easy to extend with redundancy later

**Future Evolution:**
```
Phase 1: Star           Phase 2: Dual Star       Phase 3: Mesh
   (now)               (HA routers)          (full redundancy)

    R                    R1 ─── R2              R1 ─── R2
   /|\                   /|\     /|\             /|X   X|\
  S S S                 S S S   S S S           S S S S S S
```

### Why Default-Deny Firewall?

**Decision:** Implement default-deny policy (implicit drop)

**Rationale:**
- ✅ Security best practice (principle of least privilege)
- ✅ Forces explicit thinking about required traffic
- ✅ Easier to audit (only allow rules matter)
- ✅ Reduces attack surface
- ✅ Industry standard for production systems
- ✅ Prevents accidental exposure

**Rule Philosophy:**
1. Drop everything by default
2. Only allow what's explicitly needed
3. Log denied traffic for analysis
4. Regularly review allow rules

### Why Separate Management Zone?

**Decision:** Dedicated management VLAN with highest trust

**Rationale:**
- ✅ Isolates administrative access
- ✅ Prevents lateral movement from compromised services
- ✅ Centralized monitoring and logging
- ✅ Clear audit trail
- ✅ Matches enterprise security practices
- ✅ Easier to implement strict access controls

**Security Benefits:**
- Admin credentials separated from service accounts
- MFA enforcement easier on single zone
- Can implement jump host/bastion pattern
- Monitoring doesn't traverse production traffic

---

## Troubleshooting Reference

### Common Scenarios

#### Scenario 1: Cannot Ping Between Namespaces

**Symptoms:**
```bash
$ sudo ip netns exec mgmt ping 10.10.20.10
PING 10.10.20.10 (10.10.20.10) 56(84) bytes of data.
^C
--- 10.10.20.10 ping statistics ---
5 packets transmitted, 0 received, 100% packet loss
```

**Diagnostic Steps:**

1. **Check interfaces are up:**
```bash
# Router side
sudo ip netns exec router ip link show veth-r-mgmt
sudo ip netns exec router ip link show veth-r-web

# Host side
sudo ip netns exec mgmt ip link show veth-mgmt-r
sudo ip netns exec web ip link show veth-web-r

# Expected: state UP
```

2. **Verify IP addresses:**
```bash
sudo ip netns exec router ip addr show
sudo ip netns exec mgmt ip addr show
sudo ip netns exec web ip addr show

# Expected: Correct IPs assigned
```

3. **Check routing:**
```bash
# From mgmt namespace
sudo ip netns exec mgmt ip route

# Expected: default via 10.10.10.1
```

4. **Verify IP forwarding enabled:**
```bash
sudo ip netns exec router sysctl net.ipv4.ip_forward

# Expected: net.ipv4.ip_forward = 1
```

5. **Packet capture to see traffic:**
```bash
# Terminal 1: Capture on router
sudo ip netns exec router tcpdump -i veth-r-mgmt icmp -n

# Terminal 2: Send ping
sudo ip netns exec mgmt ping -c 2 10.10.20.10

# Analyze: Do packets reach router? Do replies come back?
```

**Common Causes:**
- Interface down (forgot to bring up)
- Missing default route
- IP forwarding disabled
- Firewall blocking (check after fixing basics)

#### Scenario 2: Firewall Blocking Legitimate Traffic

**Symptoms:**
```bash
$ sudo ip netns exec web curl 10.10.30.10:8080
curl: (7) Failed to connect to 10.10.30.10 port 8080: Connection timed out
```

**Diagnostic Steps:**

1. **Check if app server is running:**
```bash
ps aux | grep "python3.*8080"
sudo ip netns exec app ss -tlnp | grep 8080

# Expected: Process listening on port 8080
```

2. **Test connectivity without firewall:**
```bash
# Temporarily allow all traffic
sudo ip netns exec router nft add rule ip filter forward accept

# Test again
sudo ip netns exec web curl 10.10.30.10:8080

# Remove temporary rule
sudo ip netns exec router nft delete rule ip filter forward handle <number>
```

3. **Check firewall rules:**
```bash
sudo ip netns exec router nft list ruleset

# Look for rule allowing DMZ → Internal on port 8080
```

4. **Watch firewall drops:**
```bash
# Terminal 1: Monitor logs
sudo dmesg -Tw | grep "FIREWALL-DROP"

# Terminal 2: Generate traffic
sudo ip netns exec web curl 10.10.30.10:8080

# Expected: See DROP logs if firewall blocking
```

5. **Verify rule specifics:**
```bash
# Check exact rule syntax
sudo ip netns exec router nft list chain ip filter forward

# Verify:
# - Source: 10.10.20.0/24
# - Destination: 10.10.30.0/24
# - Port: 8080
# - Protocol: tcp
```

**Fix:**
```bash
# Add correct rule if missing
sudo ip netns exec router nft add rule ip filter forward \
    ip saddr 10.10.20.0/24 ip daddr 10.10.30.0/24 \
    tcp dport 8080 ct state new accept
```

#### Scenario 3: Services Won't Start

**Symptoms:**
```bash
$ sudo ./scripts/05-start-services.sh
Starting web server (nginx) in DMZ...
nginx: [emerg] bind() to 10.10.20.10:80 failed (99: Cannot assign requested address)
```

**Diagnostic Steps:**

1. **Check if IP is assigned:**
```bash
sudo ip netns exec web ip addr show veth-web-r

# Expected: 10.10.20.10/24
```

2. **Check for port conflicts:**
```bash
sudo ip netns exec web ss -tlnp | grep :80

# Should be empty if nothing running
```

3. **Kill existing processes:**
```bash
sudo pkill -f "nginx.*homelab"
ps aux | grep nginx

# Verify all killed
```

4. **Start service manually to see full error:**
```bash
sudo ip netns exec web nginx -c ~/homelab/configs/nginx-web.conf

# Read full error message
```

5. **Check namespace exists:**
```bash
ip netns list | grep web

# Expected: web
```

**Common Causes:**
- Namespace doesn't exist (run setup scripts first)
- IP not assigned (run 03-configure-ips.sh)
- Process already running (kill it first)
- Wrong namespace (typo in commands)
- Config file errors (check nginx.conf syntax)

#### Scenario 4: Namespace Won't Delete

**Symptoms:**
```bash
$ sudo ip netns del web
Cannot remove namespace file "/var/run/netns/web": Device or resource busy
```

**Solution:**

1. **Find processes in namespace:**
```bash
sudo ip netns pids web

# Kill all processes
for pid in $(sudo ip netns pids web); do
    sudo kill -9 $pid
done
```

2. **Unmount namespace:**
```bash
sudo umount /var/run/netns/web
```

3. **Try deletion again:**
```bash
sudo ip netns del web
```

4. **Force removal if still stuck:**
```bash
sudo rm -f /var/run/netns/web
```

---

## Performance Characteristics

### Expected Throughput

**Network Namespace Performance:**
- **Latency:** < 0.1ms between namespaces (same host)
- **Throughput:** 10+ Gbps (limited by memory bandwidth, not network)
- **Packet rate:** 1M+ pps possible
- **Overhead:** < 5% CPU for namespace switching

**Comparison to Alternatives:**

| Method | Latency | Throughput | Overhead |
|--------|---------|------------|----------|
| Namespaces | < 0.1ms | 10+ Gbps | < 5% |
| Docker (bridge) | 0.5-1ms | 5-8 Gbps | 5-10% |
| VMs (bridged) | 1-5ms | 1-5 Gbps | 15-30% |
| Physical network | 0.5-5ms | Link speed | 0% |

**Bottlenecks:**
1. CPU for packet processing (nftables rules)
2. Memory bandwidth for large transfers
3. System call overhead for namespace operations
4. Logging (if enabled for all packets)

### Resource Consumption

**Per Namespace:**
- Memory: ~5-10 MB (base)
- CPU: Minimal when idle
- File descriptors: ~10-20

**Full Lab (5 namespaces + services):**
- Memory: ~200-300 MB total
- CPU: < 1% when idle
- Disk: < 50 MB

**Scaling Guidelines:**
- Single host: Up to 100 namespaces practical
- Beyond 100: Consider distributed approach
- Monitor: memory and file descriptor limits

---

## Compliance & Best Practices

### Security Best Practices Implemented

✅ **Network Segmentation**
- Clear zone boundaries
- Traffic filtering between zones
- Least privilege access

✅ **Defense in Depth**
- Multiple security layers
- No single point of failure for security
- Layered controls

✅ **Logging & Monitoring**
- Firewall drop logs
- Service access logs
- Audit trail capability

✅ **Least Privilege**
- Minimal inter-zone access
- Explicit allow rules only
- Database isolated from internet

✅ **Secure Defaults**
- Default-deny firewall
- No unnecessary services
- Minimal attack surface

### Industry Alignment

**CIS Controls Addressed:**
- CIS Control 12: Network Infrastructure Management
- CIS Control 13: Network Monitoring and Defense
- CIS Control 14: Security Awareness Training (educational)

**NIST Framework Alignment:**
- PR.AC: Identity Management and Access Control
- PR.DS: Data Security (through segmentation)
- PR.PT: Protective Technology (firewall)
- DE.CM: Security Continuous Monitoring

**PCI DSS Concepts:**
- Requirement 1: Firewall configuration
- Requirement 2: System hardening
- Requirement 11: Security testing (lab scenarios)

---

## References & Additional Reading

### Official Documentation

**Linux Networking:**
- [Network Namespaces Man Page](https://man7.org/linux/man-pages/man7/network_namespaces.7.html)
- [iproute2 Documentation](https://wiki.linuxfoundation.org/networking/iproute2)
- [Netfilter nftables Wiki](https://wiki.nftables.org/)

**Rocky Linux:**
- [Rocky Linux Networking Guide](https://docs.rockylinux.org/guides/network/)
- [RHEL 8 Networking Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/)

**Security:**
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Controls](https://www.cisecurity.org/controls)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

### Books

**Networking:**
- "TCP/IP Illustrated, Volume 1" by W. Richard Stevens
- "Linux Network Administrator's Guide" by Tony Bautts
- "Computer Networks" by Andrew S. Tanenbaum

**Security:**
- "The Practice of Network Security Monitoring" by Richard Bejtlich
- "Network Security Assessment" by Chris McNab
- "Practical Packet Analysis" by Chris Sanders

**Linux Administration:**
- "UNIX and Linux System Administration Handbook" by Evi Nemeth
- "The Linux Command Line" by William Shotts
- "Linux Performance" by Brendan Gregg

### Online Resources

**Learning Platforms:**
- [Linux Academy / A Cloud Guru](https://acloudguru.com)
- [Red Hat Learning Subscription](https://www.redhat.com/en/services/training-and-certification)
- [NetworkChuck YouTube Channel](https://www.youtube.com/c/NetworkChuck)

**Communities:**
- [/r/networking](https://reddit.com/r/networking)
- [/r/sysadmin](https://reddit.com/r/sysadmin)
- [/r/homelab](https://reddit.com/r/homelab)
- [Linux Foundation Training](https://training.linuxfoundation.org)

**Certifications:**
- RHCSA (Red Hat Certified System Administrator)
- RHCE (Red Hat Certified Engineer)
- CCNA (Cisco Certified Network Associate)
- CompTIA Network+
- CompTIA Security+

---

## Glossary

**Network Namespace:** Isolated network stack within a Linux kernel, providing separate network interfaces, routing tables, and firewall rules.

**veth Pair:** Virtual Ethernet pair creating a bidirectional network link between two network namespaces, functioning like a virtual cable.

**DMZ (Demilitarized Zone):** Network segment that sits between trusted internal networks and untrusted external networks, hosting public-facing services.

**Defense in Depth:** Security strategy employing multiple layers of security controls to protect resources.

**Stateful Firewall:** Firewall that tracks the state of network connections and makes decisions based on context (established connections, new connections, etc.).

**nftables:** Modern Linux firewall framework replacing iptables, providing unified configuration for packet filtering and NAT.

**Zero Trust:** Security model assuming no implicit trust and requiring verification for every access request, regardless of source.

**Least Privilege:** Security principle of granting minimum access rights necessary for users/services to perform their functions.

**VLAN (Virtual LAN):** Logical network segmentation that partitions a physical network into isolated broadcast domains.

**Three-Tier Architecture:** Application design pattern separating presentation (web), application logic, and data persistence layers.

**Jump Host/Bastion:** Hardened server providing access to a private network from an external network, acting as a gateway.

**CIDR (Classless Inter-Domain Routing):** IP address notation specifying network prefix length (e.g., /24 = 255.255.255.0).

**Default Route:** Routing table entry specifying where to send packets when no specific route matches the destination.

**Connection Tracking (conntrack):** Kernel mechanism tracking network connection states for stateful firewalling.

**MTU (Maximum Transmission Unit):** Largest packet size that can be transmitted on a network link without fragmentation.

---

## Changelog

### Version 1.0 (2024-11-08)
- Initial design documentation
- 4-zone security architecture defined
- Network topology and addressing documented
- Firewall rules specified
- Service architecture outlined
- Implementation technology described
- Scalability considerations added
- Future enhancements planned

### Future Versions

**v1.1 (Planned):**
- DNS implementation details
- DHCP server configuration
- Load balancer setup guide

**v1.2 (Planned):**
- Monitoring stack integration
- Logging architecture
- Alerting configuration

**v2.0 (Planned):**
- High availability design
- Multi-host distribution
- Container orchestration integration

---

## Document Maintenance

**Review Schedule:** Quarterly

**Last Reviewed:** 2024-11-08

**Next Review:** 2025-02-08

**Document Owner:** Lab Administrator

**Approval:** Architecture Review Board (for production deployments)

---

## Conclusion

This network design provides a solid foundation for learning enterprise datacenter networking concepts using accessible technology. The architecture balances educational value with production-like patterns, allowing learners to gain practical experience without requiring expensive hardware or cloud resources.

**Key Takeaways:**
- Security zones provide defense in depth
- Network segmentation limits blast radius
- Stateful firewalls enforce access controls
- Three-tier architecture separates concerns
- Automation enables reproducibility

**Next Steps:**
1. Review this document thoroughly
2. Implement the design using provided scripts
3. Practice troubleshooting scenarios
4. Experiment with modifications
5. Document your learning journey

**Remember:** The best way to learn networking is to build, break, and fix things. This lab provides a safe environment to do exactly that.

---

*This document is part of the Home Lab Network Simulation project. For implementation details, see README.md and the scripts/ directory.*