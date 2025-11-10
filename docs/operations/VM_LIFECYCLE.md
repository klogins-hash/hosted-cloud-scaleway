# OpenNebula VM Lifecycle Procedures

**Last Updated**: November 10, 2025
**Scope**: Frontend and Worker Nodes (fe, host01)
**Audience**: DevOps Engineers, System Administrators

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [VM Creation](#vm-creation)
3. [VM Management](#vm-management)
4. [VM Networking](#vm-networking)
5. [VM Snapshots & Backups](#vm-snapshots--backups)
6. [VM Deletion](#vm-deletion)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Access Requirements
- SSH access to frontend node: `51.159.107.100`
- SSH key: `scw/003.opennebula_instances/opennebula.pem`
- SSH user: `ubuntu`
- oneadmin user credentials (stored in `.secret`)

### Environment Setup
```bash
cd /Users/franksimpson/Desktop/hosted-cloud-scaleway
source .secret
```

### Available Resources
```bash
# Check current datastore capacity
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100 "onedatastore list"

# Check available networks
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100 "onevnet list"

# Check available hosts
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100 "onehost list"
```

---

## VM Creation

### Method 1: Deploy from Marketplace (Recommended for Testing)

#### Step 1: List Available Marketplace Images
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# List available images
onemarketapp list
EOF
```

#### Step 2: Create VM from Template
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Create VM from Alpine Linux template
onevm create --from-template "Alpine Linux 3.21" \
  --set-name "test-vm-001"
EOF
```

#### Step 3: Monitor VM Deployment
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Monitor VM status (refresh every 5 seconds)
watch -n 5 "onevm list"

# Or get detailed VM info
onevm show 0  # Replace 0 with actual VM ID
EOF
```

### Method 2: Create from Custom Template

#### Step 1: Create VM Template
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

cat > /tmp/custom_vm.tmpl << 'TEMPLATE'
NAME       = "custom-vm-001"
MEMORY     = 512
CPU        = 1
VCPU       = 1
DISK = [
  IMAGE_ID = 0  # Replace with your image ID
]
NIC = [
  NETWORK_ID = 0  # Replace with your network ID
]
TEMPLATE
EOF
```

#### Step 2: Create Template in OpenNebula
```bash
onetemplate create /tmp/custom_vm.tmpl
```

#### Step 3: Instantiate from Template
```bash
onetemplate instantiate <TEMPLATE_ID> --name "my-vm-001"
```

---

## VM Management

### Check VM Status
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# List all VMs
onevm list

# Show detailed info for VM ID 0
onevm show 0 -j | jq .
EOF
```

### Start a VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

onevm resume <VM_ID>
EOF
```

### Pause a VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

onevm suspend <VM_ID>
EOF
```

### Stop a VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

onevm shutdown <VM_ID> --hard  # Send SIGKILL
EOF
```

### Reboot a VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

onevm reboot <VM_ID>
EOF
```

### Access VM Console
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Get VNC console URL
onevm show <VM_ID> | grep GRAPHICS
EOF
```

---

## VM Networking

### Attach Network to VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Get available networks
onevnet list

# Attach network to running VM
onevm attach-nic <VM_ID> --network <NETWORK_ID>
EOF
```

### Detach Network from VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# List VM networks
onevm show <VM_ID> | grep NIC

# Detach network (NIC_ID is shown in previous command)
onevm detach-nic <VM_ID> <NIC_ID>
EOF
```

### Assign Flexible IP (Public IP)
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Get available Flexible IPs from address range
onevnet show 0  # Replace with public network ID

# Assign specific IP by updating NIC
onevm update <VM_ID> << 'UPDATE'
NIC = [
  NETWORK_ID = "0",
  IP = "51.159.X.X"  # Provide Flexible IP
]
UPDATE
EOF
```

### Access VM via Network
```bash
# For public network VMs (on pubridge)
ping 51.159.X.X
ssh ubuntu@51.159.X.X

# For private VXLAN VMs (10.1.2.x)
# Access via SSH tunnel through frontend
ssh -J ubuntu@51.159.107.100 ubuntu@10.1.2.X
```

---

## VM Snapshots & Backups

### Create VM Snapshot
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Create snapshot
onevm snapshot-create <VM_ID> "before-update-$(date +%Y%m%d)"

# List snapshots
onevm snapshot-list <VM_ID>
EOF
```

### Revert to Snapshot
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Revert to specific snapshot
onevm snapshot-revert <VM_ID> <SNAPSHOT_ID>
EOF
```

### Backup VM Disk
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Get VM disk image ID
onevm show <VM_ID> -j | jq '.VM.TEMPLATE.DISK.IMAGE_ID'

# Get image info
oneimage show <IMAGE_ID>

# Create image snapshot for backup
oneimage snapshot-flatten <IMAGE_ID> <SNAPSHOT_ID>
EOF
```

---

## VM Deletion

### Graceful Shutdown & Delete
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# 1. Gracefully shutdown VM
onevm shutdown <VM_ID>

# Wait for DONE state
sleep 30
onevm list

# 2. Delete VM (keep disks for recovery)
onevm delete <VM_ID>

# 3. Delete disks if confirmed recovered
oneimage rm <IMAGE_ID>
EOF
```

### Force Delete VM
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Force delete running VM
onevm delete <VM_ID> --force

# Or send SIGKILL and delete
onevm shutdown <VM_ID> --hard
onevm delete <VM_ID>
EOF
```

---

## Troubleshooting

### VM Won't Start
**Symptoms**: VM stuck in "PENDING" state

**Diagnostic Steps**:
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Check scheduling errors
onevm show <VM_ID> | grep ERROR

# Check host capacity
onehost list

# Check datastore space
onedatastore list
EOF
```

**Resolution**:
- Ensure target host has sufficient CPU/memory
- Ensure datastore has space (>1GB minimum)
- Check firewall rules allowing VM traffic
- Verify network bridge exists: `brctl show`

### VM Network Issues
**Symptoms**: VM cannot ping other hosts

**Diagnostic Steps**:
```bash
# 1. SSH into VM (if possible)
ssh ubuntu@51.159.X.X

# 2. Check IP configuration inside VM
ip addr show
ip route show

# 3. Check bridge configuration on host
ssh ubuntu@51.159.107.100 "brctl show"

# 4. Check VXLAN status
ssh ubuntu@51.159.107.100 "ip link show vmtovm0"
```

**Resolution**:
- Verify network is attached to VM: `onevm show <VM_ID> | grep NIC`
- Check network address ranges not conflicting
- Verify VLAN IDs match: `onevnet show 1`
- Restart network if needed: `sudo systemctl restart networking`

### VM SSH Access Issues
**Symptoms**: Cannot SSH to VM, timeout or connection refused

**Diagnostic Steps**:
```bash
# 1. Verify VM has IP address
onevm show <VM_ID> | grep IP

# 2. Test reachability
ping 51.159.X.X (for public) or ping -I br0 10.1.2.X (for private)

# 3. Check SSH service is running in VM
ssh ubuntu@51.159.107.100 "virsh list"
ssh ubuntu@51.159.107.100 "virsh console <VM_DOMAIN>"
```

**Resolution**:
- Ensure VM has network attached
- Verify VM guest OS supports SSH (boot complete)
- Check firewall allows port 22
- Verify key-based auth enabled in guest OS

### Datastore Full
**Symptoms**: VM creation fails with "not enough space"

**Diagnostic Steps**:
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Check datastore usage
onedatastore list
onedatastore show 0  # Default datastore

# Check actual disk usage
df -h /var/lib/one/datastores/
EOF
```

**Resolution**:
- Delete old/unused VM images
- Backup and remove completed snapshots
- Expand datastore by adding new storage volumes
- Migrate VMs to secondary datastore if available

### OpenNebula API Issues
**Symptoms**: API calls fail, daemon seems hung

**Diagnostic Steps**:
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
# Check OpenNebula daemon status
sudo systemctl status opennebula

# Check logs for errors
sudo tail -100 /var/log/one/oned.log

# Check if daemon is responding
sudo -u oneadmin one_auth_info
EOF
```

**Resolution**:
- Restart OpenNebula daemon: `sudo systemctl restart opennebula`
- Check database connectivity: `mysql -u one -p -h localhost`
- Review log files for specific errors
- Contact OpenNebula support if persistent

---

## Checklists

### Pre-Production Deployment Checklist
- [ ] VM has been tested on both networks (public + private)
- [ ] Network connectivity verified (ping, traceroute)
- [ ] SSH access confirmed from both frontend and external
- [ ] All required packages installed and working
- [ ] Backup/snapshot created before marking production
- [ ] Monitoring agents installed and reporting
- [ ] Security groups/firewall rules verified
- [ ] Disk space sufficient for workload
- [ ] Memory/CPU allocation matches workload requirements

### Daily Operations Checklist
- [ ] All VMs running with expected status
- [ ] Datastore capacity > 20% free space
- [ ] No persistent ERROR or WARNING messages
- [ ] Network connectivity tests passing
- [ ] Daily backups completed successfully
- [ ] OpenNebula daemon responsive (API working)
- [ ] Database replication lag (if applicable) < 1 second

### Before Major Changes
- [ ] Create full VM snapshot
- [ ] Document current VM configuration
- [ ] Notify users (if applicable)
- [ ] Backup database
- [ ] Have rollback plan documented
- [ ] Test changes on non-production VM first

---

## Command Reference

### Quick Commands
```bash
# Connect to frontend
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100

# List all VMs
ssh ubuntu@51.159.107.100 "onevm list"

# Create VM from template
ssh ubuntu@51.159.107.100 "onetemplate instantiate <TEMPLATE_ID> --name <VM_NAME>"

# Delete VM
ssh ubuntu@51.159.107.100 "onevm delete <VM_ID>"

# Get VM info
ssh ubuntu@51.159.107.100 "onevm show <VM_ID> -j" | jq .

# Monitor VM
ssh ubuntu@51.159.107.100 "watch -n 5 'onevm list'"
```

---

## References

- [OpenNebula VM Management](https://docs.opennebula.io/stable/management_and_operations/managing_virtual_machines/index.html)
- [OpenNebula Networking](https://docs.opennebula.io/stable/management_and_operations/manage_networks/index.html)
- [Scaleway Bare Metal](https://www.scaleway.com/en/docs/bare-metal/elastic-metal/)

---

**Document Version**: 1.0
**Last Updated**: November 10, 2025
**Next Review**: November 17, 2025
