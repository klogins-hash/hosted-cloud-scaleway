# OpenNebula Network Architecture

**Last Updated**: November 10, 2025
**Environment**: Scaleway Bare Metal (Paris Region - fr-par-2)

## Network Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Internet (Public)                         │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
   ┌─────────┐       ┌─────────┐      ┌──────────┐
   │51.159.  │       │51.159.  │      │Gateway   │
   │107.100  │       │109.233  │      │62.210... │
   │(FE-1)   │       │(Worker) │      │          │
   └────┬────┘       └────┬────┘      └──────────┘
        │                 │
        └─────────────────┼─────────────────────┐
                          │                     │
        ┌─────────────────┼──────────┐         │
        │                 │          │         │
    ┌───────────────────────────────────────────────┐
    │   VPC: vpc-opennebula-opennebula-scw-string  │
    │                                              │
    │  ┌──────────────────────────────────────┐   │
    │  │  Public Subnet (Flexible IPs)        │   │
    │  │  Network: 51.159.0.0/16              │   │
    │  │  Bridge: br0 (enp5s0 + VLAN)         │   │
    │  └──────────────────────────────────────┘   │
    │           ▲                    ▲             │
    │           │                    │             │
    │  ┌────────┴─────┐   ┌──────────┴──────┐    │
    │  │ fe (51....)  │   │ host01 (51...)  │    │
    │  │ 10.16.0.3    │   │ 10.16.0.2       │    │
    │  └──────┬───────┘   └──────┬──────────┘    │
    │         │                  │                │
    │  ┌──────────────────────────────├─────────────────┐
    │  │    Private Subnet 1           │                 │
    │  │    Network: 10.16.0.0/20      │                 │
    │  └──────────────────────────────┼─────────────────┘
    │                                  │
    │  ┌──────────────────────────────┴──────────────┐
    │  │   VXLAN Overlay Network (Host-to-Host)     │
    │  │   ┌─────────────────────────────────────┐  │
    │  │   │  Bridge: vmtovm0 (VXLAN)           │  │
    │  │   │  Network: 10.1.2.0/24              │  │
    │  │   │  Active VMs get IPs: 10.1.2.100+   │  │
    │  │   │  Pool Size: 48 addresses           │  │
    │  │   └─────────────────────────────────────┘  │
    │  └──────────────────────────────────────────────┘
    │
    │  ┌──────────────────────────────────────┐
    │  │  Private Subnet 2 (Reserved)         │
    │  │  Network: 10.17.0.0/20               │
    │  │  Status: Available for future use    │
    │  └──────────────────────────────────────┘
    │
    └──────────────────────────────────────────────┘
```

---

## Network Components

### 1. Public Network (Flexible IPs)

**Purpose**: External connectivity and public VM access

**Details**:
```
Network Type: Bare Metal VPC
Address Block: 51.159.0.0/16 (inherited from Scaleway)
Driver: pubridge (Linux Bridge)
Physical Device: enp5s0 (primary NIC)
Bridge: br0
VLANs: Tagged interfaces
MTU: 1500
```

**Connected Nodes**:
- Frontend (fe): 51.159.107.100
- Worker (host01): 51.159.109.233

**Capabilities**:
- Direct internet access
- Inbound port 22 (SSH)
- Inbound port 2633 (OpenNebula API)
- Inbound port 8080 (FireEdge Web UI)
- Public IP assignment to VMs via VLAN/broadcast

---

### 2. Private Management Network (10.16.0.0/20)

**Purpose**: Cluster communication and management

**Details**:
```
Network Type: VPC Private Subnet
Address Block: 10.16.0.0/20
Gateway: 10.16.0.1
Broadcast: 10.16.15.255
Hosts: 10.16.0.0 - 10.16.15.255 (4094 usable)
MTU: 1500
```

**Allocated IPs**:
```
10.16.0.1   - VPC Gateway (reserved)
10.16.0.2   - Worker (host01)
10.16.0.3   - Frontend (fe)
10.16.1.0+  - Reserved for future nodes
```

**Routing**:
```
Destination   Gateway       Interface
10.16.0.0/20  direct        vlan3000 (tagged on enp3s0)
169.254.0.0   fe's route    vlan3000
default       62.210.0.1    enp5s0 (external)
```

**DNS Resolution**:
- Internal hosts resolve via `/etc/hosts`
- External domains via 1.1.1.1 (Cloudflare)

---

### 3. VXLAN Host-to-Host Network (10.1.2.0/24)

**Purpose**: VM-to-VM communication across hypervisors

**Details**:
```
Network Type: VXLAN Overlay
VN ID: 1 (in OpenNebula)
Address Block: 10.1.2.0/24
Driver: vxlan (Linux VXLAN)
Physical Bridge: vmtovm0
VLAN ID: Automatic (AUTOMATIC_VLAN_ID: YES)
MAC address: Broadcast
MTU: 1450 (reduced for VXLAN overhead)
```

**Address Pool**:
```
Start IP: 10.1.2.100
End IP: 10.1.2.147
Total IPs: 48
Reserved: 10.1.2.1 - 10.1.2.99 (99 for network/broadcast/gateway)
```

**Key Configuration**:
```
VLAN_ID: Auto-assigned
AUTOMATIC_VLAN_ID: YES
MULTICAST: no
BRIDGE: vmtovm0
PHYDEV: vmtovm
FILTER_IP_SPOOFING: NO
FILTER_MAC_SPOOFING: NO
```

**Latency Target**: < 5ms between hosts (same datacenter)

---

## Bridge Configuration

### Frontend (fe) - 51.159.107.100

#### Bridge 1: br0 (Public, Flexible IPs)
```
┌──────────────────────────────────┐
│         Bridge: br0               │
├──────────────────────────────────┤
│                                   │
│  Physical: enp5s0 (1Gbps)        │
│  Gateway: 62.210.0.1             │
│  IP: 51.159.107.100              │
│  Subnet: 51.159.0.0/16           │
│                                   │
│  Connected VMs (via tap):         │
│  • VM with Flexible IP (IPs)      │
│  • VM 2 (IPs)                     │
│                                   │
└──────────────────────────────────┘
```

#### Bridge 2: vmtovm0 (VXLAN, VM-to-VM)
```
┌──────────────────────────────────┐
│    Bridge: vmtovm0 (VXLAN)        │
├──────────────────────────────────┤
│                                   │
│  Physical: vxlan interface       │
│  IP: 10.1.2.1 (assumed gateway)  │
│  Subnet: 10.1.2.0/24             │
│  MTU: 1450                        │
│                                   │
│  Connected VMs (via tap):         │
│  • VM A (10.1.2.100)              │
│  • VM B (10.1.2.101)              │
│                                   │
└──────────────────────────────────┘
```

#### Private Interface: enp3s0 (Management)
```
VLAN 3000 (tagged):
  IP: 10.16.0.3/20
  Gateway: 10.16.0.1
  Route to: 10.16.0.0/20 (VPC private subnet)
  Route to: 10.17.0.0/20 (reserved)
```

---

### Worker (host01) - 51.159.109.233

Same bridge configuration:
- br0: Public/Flexible IPs
- vmtovm0: VXLAN overlay
- enp3s0 VLAN 3000: Management network

---

## Network Security

### Inbound Rules (Scaleway Security Group)
```
Protocol  Port     Source        Purpose
───────────────────────────────────────────────────
TCP       22       0.0.0.0/0     SSH (admin access)
TCP       2633     10.16.0.0/20  OpenNebula API
TCP       8080     0.0.0.0/0     FireEdge (public)
TCP       5030     10.16.0.0/20  OneGate (internal)
TCP       2434     10.16.0.0/20  OneFlow (internal)
TCP       3306     10.16.0.0/20  MariaDB (internal)
ICMP      -        10.16.0.0/20  Ping (internal)
UDP       -        10.16.0.0/20  NTP, DNS
```

### Firewall Status
```bash
# Check current rules
sudo iptables -L -v

# Check bridge filtering
sudo iptables -L -v -t filter
```

---

## Routing Table

### Frontend Routing
```
Destination     Gateway            Interface    Metric
────────────────────────────────────────────────────────
default         62.210.0.1         enp5s0       0
10.16.0.0/20    direct             vlan3000     0
10.17.0.0/20    10.16.0.1          vlan3000     0
10.1.2.0/24     direct             vmtovm0      0
169.254.0.0/16  direct             lo           256
```

### VM Routing (inside VM)
```
Destination     Gateway            Interface    Method
────────────────────────────────────────────────────────
default         10.1.2.1           eth0         (DHCP on vxlan)
or
default         51.159.X.1         eth0         (DHCP on br0)
```

---

## Network Performance Characteristics

### Measured Latency
```
Frontend → Worker:     < 1ms  (same Scaleway datacenter)
Within VM (VXLAN):     < 5ms  (overlay penalty)
To Internet:           15-30ms (typical Scaleway)
```

### Throughput (Gigabit Ethernet)
```
1Gbps per interface (enp5s0)
Management: sufficient  (10.16.0.0/20)
VXLAN: sufficient (1.45Gbps after overhead)
```

### Packet Loss
```
Current: < 0.01%
Target:  < 0.1%
```

---

## DNS Configuration

### Frontend
```
/etc/netplan/00-installer-config.yaml:
  nameservers:
    addresses: [1.1.1.1, 8.8.8.8]

/etc/hosts (local resolution):
  127.0.0.1       localhost
  10.16.0.3       fe
  10.16.0.2       host01
```

### OpenNebula Internal
```
OneGate DNS:  automatically resolves VM hostnames
Metadata:     169.254.169.254
```

---

## Network Monitoring

### Key Metrics
```
1. Interface Statistics:
   - Bytes sent/received per interface
   - Packets sent/received
   - Errors and dropped packets

2. Bridge Statistics:
   - Forwarded frames
   - Bridge port status
   - Flood events

3. VXLAN Specific:
   - Encapsulation/decapsulation rate
   - Drop rate
   - Inner/outer packet counts
```

### Monitoring Commands
```bash
# Interface stats
ip -s link show

# Bridge info
brctl show
brctl showmacs br0

# VXLAN details
ip -d link show vmtovm0

# Connectivity test
ping -I 10.16.0.3 10.16.0.2  # Management
ping -I 10.1.2.1 10.1.2.100   # VXLAN

# Network throughput (install iperf3)
iperf3 -s  # Server
iperf3 -c 10.16.0.2 -t 60  # Client
```

---

## Future Network Expansion

### Phase 5 Planned Features
1. **Multiple VXLAN networks** (one per project/tenant)
2. **Network segmentation** (DMZ, app, database subnets)
3. **Load balancer network** (internal HAProxy or Scaleway LB)
4. **VPN gateway** (for remote access)

### IP Reservation for Future
```
10.17.0.0/20   - Reserved for additional private networks
10.1.3.0/24    - Reserved for additional VXLAN overlays
10.1.4.0/24    - Reserved for additional VXLAN overlays
```

---

## Troubleshooting Network Issues

### VM Cannot Reach External Host
```bash
# 1. Check VM has network attached
onevm show <VM_ID> | grep NIC

# 2. Check if br0 is functioning
brctl show br0

# 3. Check VM default route
ssh ubuntu@VM_IP "route -n"

# 4. Verify Scaleway firewall rules
# (Check Security Group in Scaleway console)
```

### High Network Latency
```bash
# 1. Measure latency
ping -I 10.16.0.3 10.16.0.2

# 2. Check for VXLAN congestion
ethtool -S vmtovm0 | grep -i drop

# 3. Check host CPU usage
top -b

# 4. Verify MTU settings
ip link show | grep mtu
```

### Broadcast Issues
```bash
# 1. Check broadcast on VXLAN
ip link show vmtovm0

# 2. Verify VLAN tagging
ip -d link show enp3s0

# 3. Check bridge forwarding
brctl showmacs vmtovm0
```

---

## Related Documents

- [VM Lifecycle Procedures](../operations/VM_LIFECYCLE.md)
- [Monitoring Setup](../operations/MONITORING_SETUP.md)
- [PROJECT_PLAN.md](../../PROJECT_PLAN.md)

---

**Document Version**: 1.0
**Last Updated**: November 10, 2025
**Next Review**: November 17, 2025
