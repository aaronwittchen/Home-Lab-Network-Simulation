# Home Lab Network Simulation

![Status: Active](https://img.shields.io/badge/Status-Active-success)
![License: MIT](https://img.shields.io/badge/License-MIT-blue)
![Platform: Linux](https://img.shields.io/badge/Platform-Rocky%20Linux-lightgrey?logo=redhat&logoColor=white)
![Scripting: Bash](https://img.shields.io/badge/Scripting-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Firewall: nftables](https://img.shields.io/badge/Firewall-nftables-00599C)
![Routing: FRR](https://img.shields.io/badge/Routing-FRR-00599C)
![Focus: Networking](https://img.shields.io/badge/Focus-Networking-orange)

**Production-style multi-tier datacenter network simulation using Linux network namespaces on Rocky Linux**

This project builds a realistic multi-tier network environment using Linux network namespaces, routing, and stateful firewalls. It is designed as a hands-on lab for learning datacenter and network engineering concepts in a controlled, repeatable environment.

---

## Project Overview

The lab environment simulates an enterprise-style datacenter with:

* Four security zones (Management, DMZ, Internal, Database)
* Virtual networking using Linux network namespaces and veth pairs
* Stateful firewall with nftables
* Working web, application, and database services
* Modular automation scripts
* Monitoring and diagnostic tools

### Key Learning Outcomes

You will learn how to:

* Design and implement network segmentation and firewall policies
* Work with Linux networking tools (`ip`, `nft`, routing)
* Deploy and connect services across multiple network zones
* Automate infrastructure setup and teardown with Bash
* Diagnose and troubleshoot connectivity issues

**Who this project is for:**

* Students or professionals learning network engineering
* System administrators and DevOps engineers
* RHCSA/RHCE and CCNA certification candidates
* Anyone wanting a deeper understanding of Linux networking internals

---

## Architecture

### Network Topology

```
                    Internet (Simulated)
                            |
                    ┌───────┴───────┐
                    │   Gateway/FW  │ 192.168.100.1
                    │   (Physical)  │
                    └───────┬───────┘
                            |
                    ┌───────┴───────┐
                    │  Core Router  │ (network namespace)
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

| VLAN | Name       | Subnet        | Gateway    | Purpose           |
| ---- | ---------- | ------------- | ---------- | ----------------- |
| 10   | Management | 10.10.10.0/24 | 10.10.10.1 | Admin/Jump hosts  |
| 20   | DMZ        | 10.10.20.0/24 | 10.10.20.1 | Public-facing web |
| 30   | Internal   | 10.10.30.0/24 | 10.10.30.1 | Application tier  |
| 40   | Database   | 10.10.40.0/24 | 10.10.40.1 | Database servers  |

Host IP allocations:

* `.1` = Router gateway
* `.10-.99` = Servers
* `.100-.199` = DHCP or dynamic pool (future)
* `.200-.254` = Reserved

### Security Zones and Firewall Policy

```
Management (VLAN 10) - High Trust
  - Can access all zones
  - Incoming SSH restricted

DMZ (VLAN 20) - Low Trust
  - Can access Internal (VLAN 30) on port 8080
  - No access to Database zone

Internal (VLAN 30) - Medium Trust
  - Can access Database (VLAN 40) on port 3306
  - Accepts traffic only from DMZ on port 8080

Database (VLAN 40) - High Trust
  - Isolated, accepts only port 3306 from Internal
```

**Firewall Summary:**

```
ACCEPT: Management (10.10.10.0/24) → ALL
ACCEPT: DMZ (10.10.20.0/24) → Internal (10.10.30.0/24):8080
ACCEPT: Internal (10.10.30.0/24) → Database (10.10.40.0/24):3306
ACCEPT: Established/Related connections
DROP:   All other traffic
```

---

## Quick Start

### Requirements

**System:**

* Rocky Linux 8 or 9 (RHEL/AlmaLinux/CentOS Stream compatible)
* Root or sudo access
* 2 GB RAM minimum
* 10 GB disk space

**Install required packages:**

```bash
sudo dnf update -y
sudo dnf install -y iproute nftables bridge-utils net-tools \
tcpdump wireshark-cli traceroute bind-utils nmap nginx python3 frr git vim tmux tree
```

### Building the Lab

```bash
# Clone and navigate
cd ~/homelab

# Make scripts executable
chmod +x scripts/*.sh

# Build everything
sudo ./scripts/setup-all.sh
```

This sets up the entire multi-tier network in about 30 seconds.

---

## Usage

### Common Commands

```bash
sudo ./scripts/setup-all.sh      # Build lab
sudo ./scripts/status.sh         # Check current state
sudo ./scripts/run-tests.sh      # Run automated tests
sudo ./scripts/monitor.sh traffic # Monitor live traffic
sudo ./scripts/destroy-all.sh    # Tear down lab
```

### Interactive Testing

```bash
sudo ip netns exec mgmt bash
ping 10.10.20.10
curl 10.10.20.10
curl 10.10.30.10:8080
exit

sudo ip netns exec web curl 10.10.30.10:8080  # Allowed
sudo ip netns exec web curl 10.10.40.10:3306  # Blocked
```

### Monitoring and Diagnostics

```bash
sudo ./scripts/monitor.sh traffic
sudo ./scripts/monitor.sh test
sudo ip netns exec router tcpdump -i veth-r-web -n
sudo ip netns exec router nft list ruleset
sudo ip netns exec router ss -tn
```

---

## Testing and Verification

After running `run-tests.sh`, the expected summary is:

```
Passed: 28 | Failed: 0
All tests passed. Lab is healthy.
```

Example manual checks:

```bash
ip netns list
sudo ip netns exec mgmt ip addr show veth-mgmt-r
sudo ip netns exec mgmt curl 10.10.20.10
sudo ip netns exec web curl --max-time 3 10.10.40.10:3306
```

---

## Learning Scenarios

**Beginner**

1. Explore namespaces and IP assignments
2. Review and understand firewall rules
3. Simulate link failures
4. Capture traffic with tcpdump

**Intermediate**
5. Add logging to the firewall
6. Implement connection rate limits
7. Add redundant web servers
8. Monitor connection tracking

**Advanced**
9. Add dynamic routing with FRR (OSPF)
10. Configure NAT for outbound access
11. Build a VPN tunnel (WireGuard)
12. Test VRRP failover with keepalived

See `docs/lab-scenarios.md` for step-by-step exercises.

---

## Troubleshooting

Common problems and fixes:

**Namespace already exists**

```bash
sudo ./scripts/destroy-all.sh
```

**No connectivity**

```bash
sudo ip netns exec router ip link show
sudo ip netns exec router sysctl net.ipv4.ip_forward
sudo ip netns exec router tcpdump -i veth-r-mgmt icmp
```

**Service not starting**

```bash
sudo pkill -f nginx; sudo pkill -f python3
sudo ip netns exec web nginx -c ~/homelab/configs/nginx-web.conf
```

More details are in `docs/troubleshooting-guide.md`.

---

## Technical Implementation

### Why Use Network Namespaces

Namespaces provide isolation similar to containers or VRFs without requiring a hypervisor. They are lightweight, fast to create, and use the real Linux networking stack.

**Advantages:**

* Minimal resource usage
* Realistic network behavior
* Easy setup and teardown
* Ideal for experimentation and learning

### Core Technologies

| Component          | Purpose                 | Real-world Equivalent    |
| ------------------ | ----------------------- | ------------------------ |
| Network namespaces | Isolated network stacks | VRFs, containers         |
| veth pairs         | Virtual Ethernet links  | Physical cabling/VLANs   |
| nftables           | Stateful firewall       | Enterprise firewalls     |
| FRR                | Dynamic routing         | Cisco IOS, Juniper JunOS |
| tcpdump            | Packet analysis         | Wireshark, hardware taps |

* Routing and subnetting
* VLAN and zone segmentation
* Firewall design and rule management
* Linux network configuration
* Automation and monitoring
* Troubleshooting and diagnostics

---

## Future Enhancements

### Phase 2 – Extended Features

1. Add DNS (BIND or dnsmasq)
2. Implement load balancing (HAProxy, Nginx)
3. Monitoring stack (Prometheus, Grafana)
4. Centralized logging (Loki or ELK)
5. Ansible automation

### Phase 3 – Advanced Networking

6. VPNs and encrypted tunnels
7. Containerized integration
8. Software-defined networking
9. Security enhancements (IDS/IPS, SELinux)
10. High availability and redundancy

---

## Documentation

* `docs/network-design.md` – Detailed architecture
* `docs/troubleshooting-guide.md` – Diagnostics
* `docs/lab-scenarios.md` – Exercises and challenges

---

## License

This project is open source and intended for educational and personal use.


## Project Summary

**Key Features**

* Four-zone network topology
* Modular setup scripts
* Stateful nftables firewall
* Service-based traffic flows
* Automated testing and monitoring

**Skills Covered**

* Linux networking and routing
* Firewall and security design
* Service deployment and connectivity
* Infrastructure automation
* Network troubleshooting

**Highlights**

* Runs entirely on a single Linux VM
* Fully scriptable and reproducible
* Clear architecture and documentation
* Extensible for advanced experiments
