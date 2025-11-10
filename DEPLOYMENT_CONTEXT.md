# OpenNebula Hosted Cloud on Scaleway - Deployment Context

**Date**: November 10, 2025
**Status**: ✅ Infrastructure Complete | 🔄 OpenNebula Deployment In Progress

## Executive Summary

Successfully deployed complete infrastructure for OpenNebula Hosted Cloud on Scaleway bare-metal servers. All 5 Terraform modules executed successfully, creating a production-ready cloud computing environment with 2 EM-A610R-NVMe servers in Paris region.

## Deployment Timeline

### Phase 1: Infrastructure Provisioning (Completed)

#### Module 001: Terraform State Management ✅
- **Purpose**: Bootstrap state bucket and project metadata
- **Status**: Deployed successfully
- **Outputs**:
  - S3 bucket: `opennebula-opennebula-scw-string-tfstates`
  - Scaleway Project ID: `93cee4fb-02ea-4951-a2a3-573885f04a98`

#### Module 002: VPC & Private Networks ✅
- **Purpose**: Create networking infrastructure
- **Status**: Deployed successfully
- **Outputs**:
  - VPC: `vpc-opennebula-opennebula-scw`
  - Private network blocks: `10.16.0.0/20` and `10.17.0.0/20`
  - VLAN routing configured for multi-host communication

#### Module 003: OpenNebula Instances ✅
- **Purpose**: Provision bare-metal servers
- **Status**: Deployed successfully
- **Server Details**:

  **Frontend Server** (opennebula-web)
  - Public IP: `51.159.107.100`
  - Private IP: `10.16.0.3`
  - Server ID: `fr-par-2/1fc164dc-bd7a-4949-abc1-a170e676d350`
  - Hostname: `fe`
  - Role: Frontend + Node (hypervisor)

  **Worker Server** (opennebula-worker-0)
  - Public IP: `51.159.109.233`
  - Private IP: `10.16.0.2`
  - Server ID: `fr-par-2/6cfd1b44-eafe-456a-a420-4640213756d7`
  - Hostname: `host01`
  - Role: Node (hypervisor only)

- **SSH Configuration**:
  - SSH key: `scw/003.opennebula_instances/opennebula.pem`
  - SSH user: `ubuntu`
  - Connectivity: ✅ Verified via Ansible ping

#### Module 004: Network Configuration ✅
- **Purpose**: Configure networking with Netplan and bridges
- **Status**: Deployed successfully
- **Configuration**:
  - Netplan applied to both servers
  - Bridge `br0`: Public/Flexible IP traffic (enp5s0)
  - Bridge `vmtovm0`: Host-to-host VXLAN communication
  - VLAN subinterfaces properly tagged for private routing
  - Gateway configured: `62.210.0.1`
  - DNS: `1.1.1.1`

#### Module 005: IAM & Inventories ✅
- **Purpose**: Create IAM resources and generate Ansible inventory
- **Status**: Deployed successfully
- **IAM Resources Created**:
  - Application: `opennebula-flexip-opennebula-opennebula-scw-string`
  - Application ID: `28b37f21-a1d9-4438-8397-632b3cafed4f`
  - Group: `opennebula-flexip-opennebula-opennebula-scw-string-group`
  - Group ID: `8e24d02f-478a-4d65-a34e-a756524dbb22`
  - Policy: `opennebula-flexip-opennebula-opennebula-scw-string-policy`
  - Policy ID: `cbbee162-78ec-47ac-961d-0b5565ca0fa7`
  - API Key: `SCW2KBNTB9PB9XAZTTZ7`

- **Permissions Applied**:
  - `ElasticMetalFullAccess`: Full access to bare-metal resources
  - `IPAMFullAccess`: Full access to IP management (Flexible IPs)

- **Inventory Generated**:
  - Location: `scw/005.opennebula_inventories/generated/inventory.yml`
  - Ansible groups: `frontend`, `node`
  - All server metadata pre-configured for OpenNebula deployment

### Phase 2: OpenNebula Deployment (In Progress)

#### Status: 🔄 Running Background Deployment
- **Command**: `make deployment`
- **Log Location**: `/tmp/opennebula_deployment.log`
- **Current Stage**: Installing OpenNebula repositories and dependencies
- **Estimated Duration**: 30-60 minutes

**Tasks Being Performed**:
- Install OpenNebula 7.0.0 base services
- Configure MariaDB database backend
- Set up KVM hypervisor on both nodes
- Install and configure Prometheus monitoring
- Create OpenNebula user accounts (oneadmin)
- Configure firewall and networking for services
- Deploy API gateway and UI services (`gate`, `flow`, `fireedge`)

### Phase 3: Remaining Steps

#### 3a. Apply Scaleway-Specific Drivers (After deployment completes)
```bash
cd /Users/franksimpson/Desktop/hosted-cloud-scaleway
source .secret
make specifics
```

**Purpose**: Install custom VNM bridge hooks for Flexible IP management

#### 3b. Run Validation Suite (After specifics completes)
```bash
make validation
```

**Validates**:
- Core service health (oned, gate, flow, fireedge)
- Storage performance (benchmark VM)
- Network performance (iperf, ping matrix)
- Connectivity across all hosts
- Marketplace functionality (Alpine deployment test)

## Infrastructure Architecture

### Network Topology
```
┌─────────────────────────────────────────────────┐
│         Scaleway Cloud (fr-par-2)               │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │        VPC: vpc-opennebula-scw           │  │
│  │                                          │  │
│  │  ┌─────────────────────────────────┐    │  │
│  │  │ Private Subnet: 10.16.0.0/20    │    │  │
│  │  │                                 │    │  │
│  │  │ ┌──────────────┐ ┌───────────┐ │    │  │
│  │  │ │  Frontend    │ │  Worker   │ │    │  │
│  │  │ │ 10.16.0.3    │ │ 10.16.0.2 │ │    │  │
│  │  │ └──────────────┘ └───────────┘ │    │  │
│  │  │                                 │    │  │
│  │  │ ┌─────────────────────────────┐ │    │  │
│  │  │ │  VXLAN Network: 10.1.2.0/24 │ │    │  │
│  │  │ │  (vmtovm0 bridge)           │ │    │  │
│  │  │ └─────────────────────────────┘ │    │  │
│  │  └─────────────────────────────────┘    │  │
│  │                                          │  │
│  │  ┌─────────────────────────────────┐    │  │
│  │  │ Private Subnet: 10.17.0.0/20    │    │  │
│  │  │ (optional, reserved)            │    │  │
│  │  └─────────────────────────────────┘    │  │
│  └──────────────────────────────────────────┘  │
│           │                      │              │
└───────────┼──────────────────────┼──────────────┘
            │                      │
        ┌───────────┐          ┌──────────┐
        │51.159...  │          │51.159... │
        │107.100    │          │109.233   │
        └───────────┘          └──────────┘
```

### Services & Ports
- **Frontend (51.159.107.100)**
  - SSH: 22
  - OpenNebula API: 2633
  - OneGate: 5030
  - OneFlow: 2434
  - FireEdge: 8080
  - MariaDB: 3306

- **Worker (51.159.109.233)**
  - SSH: 22
  - KVM/libvirt daemon: 16509
  - MariaDB (optional replica): 3306

## Configuration Details

### Terraform Variables (terraform.tfvars)
```yaml
tfstate: opennebula-opennebula-scw-string-tfstates
region: fr-par
zone: fr-par-2
project_fullname: opennebula-opennebula-scw-string
private_subnet: 10.16.0.0/20
worker_count: 1
one_password: your_opennebula_password
scw_secret_key: a8236888-6261-4b2b-b717-6cd339e907bf
flexible_ip_permission_sets:
  - ElasticMetalFullAccess
  - IPAMFullAccess
```

### Ansible Inventory (inventory/scaleway.yml)
- **Ansible user**: ubuntu
- **OpenNebula version**: 7.0.0
- **Database**: MariaDB
- **Virtual Networks Configured**:
  - `pubridge`: Public/Flexible IP bridge network
  - `vxlan`: Host-to-host VXLAN overlay

### Scaleway Configuration
- **Region**: Fr-Par (Paris)
- **Zone**: fr-par-2
- **Server SKU**: EM-A610R-NVMe
- **Network**: VPC with private networking
- **Flexible IPs**: Configured and ready for VM assignment

## Key Files & Locations

| Description | Path |
|-------------|------|
| SSH Private Key | `scw/003.opennebula_instances/opennebula.pem` |
| Ansible Inventory | `scw/005.opennebula_inventories/generated/inventory.yml` |
| Secrets/Credentials | `.secret` (git-ignored) |
| Deployment Log | `/tmp/opennebula_deployment.log` |
| Terraform States | Local backends in each module directory |
| Playbooks | `playbooks/scaleway.yml` |
| Custom Roles | `roles/one-driver/` (Flexible IP driver) |

## Monitoring & Troubleshooting

### Check Deployment Progress
```bash
# Monitor live deployment
tail -f /tmp/opennebula_deployment.log

# Check if deployment is running
ps aux | grep "make deployment"

# SSH to frontend
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100
```

### Verify Services (After Deployment)
```bash
# Check OpenNebula services on frontend
ssh ubuntu@51.159.107.100 "sudo systemctl status opennebula"
ssh ubuntu@51.159.107.100 "sudo systemctl status opennebula-gate"
ssh ubuntu@51.159.107.100 "sudo systemctl status opennebula-flow"

# Check hypervisor on worker
ssh ubuntu@51.159.109.233 "sudo systemctl status libvirtd"

# View OpenNebula logs
ssh ubuntu@51.159.107.100 "sudo tail -f /var/log/one/oned.log"
```

### Verify Networking
```bash
# Test connectivity between nodes
ansible -i inventory/scaleway.yml all -m ping -b

# Check network configuration
ssh ubuntu@51.159.107.100 "ip addr show"
ssh ubuntu@51.159.107.100 "ip route show"
ssh ubuntu@51.159.107.100 "brctl show"
```

## Next Steps

1. **Monitor Deployment** (currently running):
   - Watch `/tmp/opennebula_deployment.log` for completion
   - Expected duration: 30-60 minutes

2. **Apply Scaleway Drivers**:
   ```bash
   make specifics
   ```
   - Installs VNM bridge hooks for Flexible IP allocation
   - Configures driver authentication
   - Deploys monitoring agents

3. **Run Validation**:
   ```bash
   make validation
   ```
   - Confirms all services operational
   - Tests network and storage performance
   - Validates marketplace integration

4. **Access OpenNebula**:
   - Web UI: `https://51.159.107.100:8080` (FireEdge)
   - API: `xmlrpc https://51.159.107.100:2633`
   - User: `oneadmin`
   - Password: (from `.secret` file)

## Troubleshooting Guide

### Issue: Deployment Timeout
**Solution**: Check SSH connectivity, verify firewall rules, review logs for specific errors

### Issue: Network Connectivity Problems
**Solution**: Verify Netplan configuration, check VLAN tags, confirm VPC settings

### Issue: IAM Policy Errors
**Solution**: Ensure permission_set_names includes valid Scaleway permission sets (ElasticMetalFullAccess, IPAMFullAccess)

### Issue: TLS Provider Version Incompatibility
**Solution**: Use TLS provider >=4.0.0 for ARM64 macOS compatibility

## References

- **Deployment Guide**: `deployment_guide.md`
- **OpenNebula Docs**: https://docs.opennebula.io/
- **Scaleway Docs**: https://www.scaleway.com/en/docs/
- **Terraform/OpenTofu**: https://opentofu.org/

## Contact & Support

For issues or questions:
1. Check log files: `/tmp/opennebula_deployment.log`
2. Review error messages in Ansible output
3. Consult deployment guide for module-specific issues
4. Contact OpenNebula community: https://opennebula.io/community/

---

**Deployment Context Generated**: November 10, 2025, 2:11 PM CST
**Infrastructure Status**: ✅ Ready
**Service Status**: 🔄 Deploying
**Next Check Point**: ~3:00 PM CST (after deployment completes)
