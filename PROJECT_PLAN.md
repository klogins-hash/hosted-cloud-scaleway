# OpenNebula Hosted Cloud on Scaleway - Project Plan

**Last Updated**: November 10, 2025
**Status**: Infrastructure Complete | Deployment Complete | Planning Phase

## Executive Summary

Successfully deployed a fully functional OpenNebula 7.0.0 hosted cloud platform on Scaleway bare-metal infrastructure. The deployment includes:

- ✅ **Infrastructure**: 2 EM-A610R-NVMe bare-metal servers in Paris region
- ✅ **Networking**: VPC with public (Flexible IP) and private (VXLAN) networks
- ✅ **OpenNebula Core**: All services deployed and verified operational
- ✅ **Database**: MariaDB with persistent storage backend
- ✅ **Scaleway Integration**: Custom VNM drivers for Flexible IP management
- ✅ **KVM Hypervisor**: Configured on both frontend and worker nodes

This project plan outlines the recommended roadmap for the next 6 months of development, testing, hardening, and production operations.

---

## Current Deployment Status

### ✅ Completed Milestones

| Component | Status | Details |
|-----------|--------|---------|
| Terraform Infrastructure | ✅ Complete | 5 modules, all resources provisioned |
| Bare-Metal Instances | ✅ Complete | 2 servers running, SSH verified |
| Network Configuration | ✅ Complete | VPC, subnets, bridges, VXLAN overlay |
| OpenNebula Installation | ✅ Complete | 7.0.0 deployed with MariaDB backend |
| Scaleway IAM Setup | ✅ Complete | Application, group, policy configured |
| Custom Drivers | ✅ Complete | Flexible IP VNM hooks installed |
| Service Verification | ✅ Complete | All 6 core services running and healthy |

### Current Infrastructure Details

**Frontend Node**
- Host: `fe` (51.159.107.100)
- Role: Frontend + Hypervisor
- CPU: 12 cores, RAM: 32 GB, Storage: 2TB NVMe
- Services: oned, fireedge, onegate, oneflow, mariadb, libvirtd

**Worker Node**
- Host: `host01` (51.159.109.233)
- Role: Hypervisor
- CPU: 12 cores, RAM: 32 GB, Storage: 2TB NVMe
- Services: libvirtd, monitoring agents

**Virtual Networks**
- `pubridge`: Public bridge for Flexible IP allocation (51.159.0.0/16)
- `vxlan`: Host-to-host VXLAN overlay (10.1.2.0/24) with 48 IP addresses

---

## 6-Month Roadmap

### Phase 1: Production Readiness & Testing (Weeks 1-2)

**Objective**: Validate deployment and prepare for production workloads

#### 1.1 Comprehensive Validation Suite
- **Task**: Execute full validation pipeline
- **Command**: `make validation`
- **Expected Outputs**:
  - Service health checks (oned, gate, flow, fireedge daemons)
  - Network performance metrics (iperf, latency, packet loss)
  - Storage performance benchmarks
  - VM lifecycle testing (create, migrate, snapshot, delete)
  - Marketplace functionality validation
- **Success Criteria**:
  - All services responding normally
  - Network latency < 5ms between hosts
  - Storage I/O > 100MB/s
  - VM deployment time < 30 seconds

#### 1.2 Initial VM Deployment
- **Task**: Launch test VMs on both networks
- **Expected**:
  - Public bridge VM with Flexible IP (external connectivity)
  - VXLAN VM with private IP (internal network)
  - Alpine Linux test instances for rapid iteration
- **Validation**:
  - VM ping latency
  - SSH connectivity to both VMs
  - Internet connectivity from public VM
  - Cross-VM communication on VXLAN

#### 1.3 Documentation Generation
- **Task**: Create operational runbooks
- **Deliverables**:
  - VM lifecycle procedures (launch, stop, delete)
  - Network management guide (create networks, assign IPs)
  - Troubleshooting playbook
  - Disaster recovery procedures
  - Credentials and access management guide
- **Location**: Create `docs/operations/` directory

#### 1.4 Backup Strategy
- **Task**: Define and test backup procedures
- **Components**:
  - VM snapshot strategy (daily, weekly, monthly retentions)
  - Database backup procedures (MariaDB dumps)
  - Configuration backups (Terraform state, inventory)
  - Recovery Time Objective (RTO) and Recovery Point Objective (RPO) targets

---

### Phase 2: Monitoring & Observability (Weeks 3-4)

**Objective**: Implement comprehensive infrastructure monitoring

#### 2.1 Prometheus Setup
- **Task**: Configure Prometheus instance on frontend
- **Components**:
  - OpenNebula exporter (via already-deployed collectd)
  - Node exporters on both hosts
  - MariaDB exporter
  - libvirt exporter (VM metrics)
- **Metrics to Track**:
  - Host CPU, Memory, Disk, Network utilization
  - OpenNebula queue sizes and processing times
  - MariaDB connections and query performance
  - VM resource consumption (CPU, RAM, disk)

#### 2.2 Grafana Dashboards
- **Task**: Create visualization dashboards
- **Recommended Dashboards**:
  - Infrastructure overview (host health, resource allocation)
  - OpenNebula operational metrics (VMs deployed, API latency)
  - Network performance (throughput, packet loss, latency)
  - Storage performance (I/O patterns, capacity trends)
  - Database health (connections, query performance)
- **Launch**: `https://51.159.107.100:3000` (port TBD)

#### 2.3 Alerting Configuration
- **Task**: Set up Prometheus alerting rules
- **Critical Alerts**:
  - Host CPU > 90% for 5 minutes
  - Memory usage > 85%
  - Disk > 80% capacity
  - OpenNebula daemon down
  - MariaDB replication lag > 1 second
  - VM creation failures
- **Notification Channels**: Email, Slack (configure in Phase 3)

#### 2.4 Centralized Logging (Optional Phase 2.5)
- **Task**: Set up ELK stack or similar
- **Components**: Filebeat, Logstash, Elasticsearch, Kibana
- **Logs to Centralize**:
  - OpenNebula daemon logs (`/var/log/one/oned.log`)
  - Nginx/API logs
  - Ansible deployment logs
  - Terraform execution logs

---

### Phase 3: Security Hardening (Weeks 5-6)

**Objective**: Secure the platform for production use

#### 3.1 Access Control & Authentication
- **Task**: Configure OpenNebula user management
- **Components**:
  - Create operational user accounts (beyond oneadmin)
  - Configure role-based access control (RBAC)
  - Set resource quotas and permissions
  - Implement API token-based authentication
- **Users to Create**:
  - `admin`: Full platform administration
  - `operator`: VM and network operations
  - `developer`: Limited sandbox access
  - `auditor`: Read-only access

#### 3.2 Network Security
- **Task**: Configure firewall and network policies
- **Inbound Rules**:
  - SSH (22): Restricted to admin networks
  - API (2633): Restricted to internal network + VPN
  - FireEdge (8080): Public but HTTPS-only
  - OneGate (5030): Internal/private only
  - OneFlow (2434): Internal/private only
- **Outbound Rules**:
  - Allow marketplace access (for image downloads)
  - Allow NTP for time sync
  - Allow DNS for name resolution
  - Restrict other egress

#### 3.3 TLS/SSL Configuration
- **Task**: Deploy proper certificates
- **Components**:
  - Generate or import SSL certificates
  - Configure HTTPS on FireEdge
  - Set up certificate auto-renewal (Let's Encrypt)
  - Configure API TLS settings
  - Document certificate management procedures

#### 3.4 Data Protection
- **Task**: Implement encryption at rest
- **Components**:
  - Enable full-disk encryption on both bare-metal nodes (at Scaleway level)
  - Configure encrypted backups
  - Set up secrets management (HashiCorp Vault or similar)
  - Secure credential storage and rotation

#### 3.5 Audit & Compliance
- **Task**: Enable comprehensive audit logging
- **Audit Trails**:
  - User authentication logs
  - API call logging
  - Resource creation/modification logs
  - Administrative actions
- **Compliance**: Document for SOC 2, GDPR, or other regulatory requirements

---

### Phase 4: Advanced Features & Optimization (Weeks 7-10)

**Objective**: Enhance capabilities and optimize performance

#### 4.1 Storage Expansion
- **Task**: Add secondary datastores
- **Options**:
  - Scaleway Object Storage (S3-compatible) for VM backups
  - Additional NVMe volumes (if required)
  - Network storage (NFS/iSCSI) for shared VM data
- **Configuration**:
  - Create datastore resources in OpenNebula
  - Configure automatic VM migration policies
  - Set up tiering (hot/warm/cold storage)

#### 4.2 High Availability (HA) Configuration
- **Task**: Set up OpenNebula HA (if desired)
- **Components**:
  - MariaDB replication setup
  - OpenNebula daemon failover
  - Floating VIP for frontend services
  - Heartbeat/keepalived configuration
- **Note**: Optional - evaluate if needed for SLA requirements

#### 4.3 Performance Tuning
- **Task**: Optimize system for production workloads
- **Areas**:
  - MariaDB query optimization
  - Libvirt/KVM performance tuning
  - Network bridge optimization
  - Storage I/O scheduling
  - Memory and CPU affinity policies
- **Benchmarking**: Baseline with sysbench, fio, iperf

#### 4.4 Multi-Tenancy Support
- **Task**: Enable multi-user/multi-project capabilities
- **Components**:
  - Create multiple OpenNebula groups
  - Configure project-based resource allocation
  - Implement chargeback/cost allocation
  - Set up resource quotas per project
  - Create separate VNets per project/tenant

#### 4.5 Image Management
- **Task**: Build and manage VM image library
- **Images to Create**:
  - Ubuntu 20.04/22.04 base images
  - CentOS/AlmaLinux base images
  - Windows Server 2019/2022 (if needed)
  - Specialized application stacks
- **Management**:
  - Version control of VM images
  - Automated image building pipeline (Packer)
  - Image marketplace integration

---

### Phase 5: Advanced Networking (Weeks 11-12)

**Objective**: Support complex networking scenarios

#### 5.1 Network Segmentation
- **Task**: Create multiple virtual networks for different purposes
- **Networks to Create**:
  - Management network (private, restricted access)
  - Application network (internal VM-to-VM)
  - DMZ network (public-facing services)
  - Database network (isolated, encrypted)
  - Storage network (optimized for I/O)
- **Security Groups**: Configure per-network firewall rules

#### 5.2 Load Balancing
- **Task**: Implement load balancing for VMs
- **Options**:
  - HAProxy VM for internal load balancing
  - Scaleway Load Balancer integration
  - OpenNebula service discovery and DNS
- **Use Cases**: Web servers, API backends, databases

#### 5.3 VPN & Secure Access
- **Task**: Set up VPN gateway
- **Options**:
  - WireGuard VPN on a dedicated VM
  - OpenVPN server for remote access
  - IPSec tunneling for site-to-site connectivity
- **Purpose**: Secure remote access for operators and developers

#### 5.4 Network Monitoring
- **Task**: Deep packet inspection and flow monitoring
- **Tools**:
  - NetFlow/sFlow collection
  - Flowmon or similar traffic analysis
  - Bandwidth utilization tracking per VM
  - DDoS protection evaluation

---

### Phase 6: Production Operations & Continuous Improvement (Weeks 13+)

**Objective**: Establish operational excellence and continuous improvement

#### 6.1 Automated Testing & CI/CD
- **Task**: Set up automated infrastructure testing
- **Components**:
  - Terraform plan validation
  - Ansible playbook linting
  - VM deployment testing (Infrastructure as Code)
  - Network connectivity tests
  - Application smoke tests on deployed VMs
- **Tools**: GitHub Actions, GitLab CI, or Jenkins

#### 6.2 Disaster Recovery & Business Continuity
- **Task**: Execute DR drills
- **Scenarios to Test**:
  - Single node failure
  - Complete site failure
  - Database corruption
  - Network partition
  - Ransomware simulation
- **Success Criteria**: RTO < 1 hour, RPO < 15 minutes

#### 6.3 Capacity Planning
- **Task**: Monitor and forecast resource needs
- **Metrics to Track**:
  - CPU and memory utilization trends
  - Storage growth rate
  - Network bandwidth consumption
  - VM deployment frequency
- **Actions**: Plan for upgrades, additional nodes, or regions

#### 6.4 Cost Optimization
- **Task**: Optimize cloud spending
- **Areas**:
  - Evaluate instance sizing vs. actual usage
  - Reserved capacity planning
  - Network egress optimization
  - Storage tiering efficiency
  - Scaleway billing analysis and forecasting

#### 6.5 Continuous Improvement
- **Task**: Establish improvement process
- **Processes**:
  - Weekly operational reviews
  - Monthly capacity/performance reviews
  - Quarterly security audits
  - Semi-annual disaster recovery drills
  - Annual architecture reviews
- **Documentation**: Maintain runbooks and playbooks

---

## Resource Requirements & Timeline

### Personnel
- **DevOps Engineer**: Full-time for all phases
- **System Administrator**: Part-time from Phase 2 onwards
- **Security Officer**: Consultation during Phase 3 and 5

### Infrastructure Capacity
- **Computation**: 24 cores, 64GB RAM (current allocation)
- **Storage**: 4TB NVMe available
- **Network**: Current VPC and subnets suitable for all phases
- **Est. Scaleway Cost**: ~$2,000-3,000/month (depending on workload)

### External Dependencies
- **Scaleway API**: No additional licenses required
- **OpenNebula**: Community edition (free) or Enterprise support contract
- **Monitoring Stack**: Prometheus/Grafana (free), or managed alternative
- **Optional**: ELK Stack, HashiCorp Vault, load balancer (additional cost)

---

## Success Metrics & KPIs

### Infrastructure Metrics
- **Availability**: Target 99.9% uptime (9 hours/year downtime)
- **Performance**: VM deployment < 30 seconds, API response < 500ms
- **Capacity**: CPU utilization 60-75%, Memory 65-80%, Disk 70-80%

### Operational Metrics
- **MTTR** (Mean Time To Recover): < 30 minutes for node failures
- **MTTF** (Mean Time To Failure): > 2,000 hours per host
- **Alert Response**: Critical alerts acknowledged within 15 minutes

### Security Metrics
- **Compliance**: 100% of security recommendations implemented
- **Audit Trail**: 100% of administrative actions logged
- **Incident Response**: Security incidents resolved within 1 hour

### User Satisfaction
- **API Availability**: > 99.95%
- **Support Response**: < 24 hours for non-critical issues
- **Documentation Completeness**: All operational procedures documented

---

## Risk Assessment & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Single Node Failure | High | Medium | HA setup, automated failover in Phase 4 |
| Network Partition | Medium | High | Implement VPN, redundant connectivity |
| Database Corruption | Low | Critical | Regular backups, replication in Phase 4 |
| DDoS Attack | Medium | High | WAF, rate limiting, DDoS protection service |
| Token/Credential Breach | Medium | Critical | Rotate credentials monthly, vault integration |
| Storage Capacity Exhaustion | Medium | Medium | Capacity monitoring, tiering strategy Phase 4 |
| Scaleway API Degradation | Low | Medium | Error handling, retry logic, manual recovery |

---

## Implementation Strategy

### Sprint-Based Approach
- **Each 2-week sprint**: One phase component with clear deliverables
- **Daily standups**: 15-minute sync on progress and blockers
- **Weekly reviews**: Assess sprint completion and adjust plan

### Quality Assurance
- **Code Review**: All changes reviewed before deployment
- **Testing**: Manual + automated testing for each phase
- **Documentation**: Every feature must include user documentation
- **Sign-off**: Product owner approval before phase completion

### Rollback Plan
- Keep previous Terraform state files for quick infrastructure rollback
- Maintain VM snapshots before major changes
- Document rollback procedures for each phase
- Test rollback procedures quarterly

---

## Phase Dependencies & Critical Path

```
Phase 1 (Testing): 2 weeks
         ↓
Phase 2 (Monitoring): 2 weeks
         ↓
Phase 3 (Security): 2 weeks
         ├─→ Phase 4 (Optimization): 4 weeks (can run parallel to Phase 3)
         ├─→ Phase 5 (Networking): 2 weeks (requires Phase 3)
         └─→ Phase 6 (Operations): Ongoing

Critical Path: Phase 1 → Phase 2 → Phase 3 → Phase 6
Parallel Paths: Phase 4 (after Phase 2), Phase 5 (after Phase 3)
```

---

## Detailed Task Breakdown

### Phase 1 Detailed Tasks
- [ ] Execute validation suite and document results
- [ ] Deploy test VMs on public and private networks
- [ ] Validate VM networking (ping, SSH, internet connectivity)
- [ ] Create initial documentation directory structure
- [ ] Document VM lifecycle procedures
- [ ] Define backup RTO/RPO targets
- [ ] Create backup test scripts

### Phase 2 Detailed Tasks
- [ ] Install Prometheus instance
- [ ] Deploy node exporters on both hosts
- [ ] Configure OpenNebula metrics collection
- [ ] Build Grafana dashboards (4+ main dashboards)
- [ ] Create alert rules and test alerting
- [ ] (Optional) Set up centralized logging solution

### Phase 3 Detailed Tasks
- [ ] Document current access control state
- [ ] Create user roles and groups in OpenNebula
- [ ] Configure network security rules at Scaleway level
- [ ] Generate and install TLS certificates
- [ ] Set up secrets management solution
- [ ] Enable audit logging for all components
- [ ] Create security documentation and procedures

### Phase 4 Detailed Tasks
- [ ] Evaluate storage requirements and options
- [ ] Provision secondary datastore(s)
- [ ] Assess OpenNebula HA requirements
- [ ] Set up performance monitoring baseline
- [ ] Document performance tuning recommendations
- [ ] Create image building pipeline
- [ ] Build 3-5 base VM images

### Phase 5 Detailed Tasks
- [ ] Design network segmentation architecture
- [ ] Create management, application, DMZ networks
- [ ] Implement load balancer (HAProxy or cloud LB)
- [ ] Deploy VPN gateway
- [ ] Configure network monitoring tools
- [ ] Document network topology and addressing

### Phase 6 Detailed Tasks
- [ ] Set up CI/CD pipeline for infrastructure testing
- [ ] Create comprehensive test suite
- [ ] Schedule and execute DR drills
- [ ] Establish capacity planning process
- [ ] Analyze costs and optimization opportunities
- [ ] Create continuous improvement dashboard

---

## Documentation Requirements

### To Be Created
1. **Operations Manual** (`docs/operations/`)
   - VM lifecycle procedures
   - Network management guide
   - Troubleshooting playbook
   - Emergency procedures

2. **Architecture Documentation** (`docs/architecture/`)
   - Network topology diagrams (updated)
   - Component interaction diagrams
   - Data flow diagrams
   - Backup architecture

3. **Security Documentation** (`docs/security/`)
   - Security policies
   - Access control procedures
   - Incident response playbook
   - Compliance checklist

4. **Developer Guide** (`docs/development/`)
   - API documentation
   - VM image creation guide
   - Custom driver development
   - Contributing guidelines

### Existing Documentation
- DEPLOYMENT_CONTEXT.md (current)
- Infrastructure as Code (Terraform modules)
- Ansible playbooks with detailed comments

---

## Success Criteria for Project Completion

### By End of Month 1
- ✅ Validation suite executed successfully
- ✅ Test VMs deployed and validated
- ✅ Initial operational documentation created
- ✅ Backup strategy defined and tested

### By End of Month 3
- ✅ Comprehensive monitoring in place
- ✅ 90%+ of security recommendations implemented
- ✅ Performance baselines established
- ✅ HA architecture evaluated (with recommendation)

### By End of Month 6
- ✅ Complete operational documentation
- ✅ 100% security hardening complete
- ✅ Advanced features (storage, HA) implemented
- ✅ Multi-tenant support operational
- ✅ Automated CI/CD testing pipeline active
- ✅ DR procedures tested and documented
- ✅ Platform ready for production workloads

---

## Decision Points & Sign-Offs

| Phase | Decision | Owner | Timeline |
|-------|----------|-------|----------|
| 1 | Proceed to Phase 2? | DevOps Lead | End Week 2 |
| 2 | Select monitoring solution | System Admin | End Week 4 |
| 3 | Implement HA? | Infrastructure Lead | End Week 6 |
| 4 | Add secondary storage? | Storage Architect | End Week 10 |
| 5 | Deploy load balancer? | Network Team | End Week 12 |
| 6 | Production launch approval | Platform Owner | Week 13 |

---

## Budget Estimation

### Monthly Scaleway Infrastructure Costs
```
2x EM-A610R-NVMe (€350/month each):     €700
VPC + Networking:                       €50
Scaleway Object Storage (backup):       €50
API calls and data transfer:            €50
---
Total Monthly Est.:                     €850/month (~$920)
```

### Recommended Additional Services (Optional)
```
Managed Monitoring (DataDog/New Relic):  ~$200-500/month
Load Balancer (Scaleway LB):             ~€100-200/month
DDoS Protection:                         ~€100/month
---
Total with Services:                     ~$1,500-2,000/month
```

---

## Next Immediate Actions

### Recommended (Start This Week)
1. ✅ **Create this project plan** (DONE)
2. **Execute Phase 1 validation**
   ```bash
   cd /Users/franksimpson/Desktop/hosted-cloud-scaleway
   make validation
   ```
3. **Deploy test VMs**
   - Launch Alpine instance on pubridge network
   - Launch Alpine instance on vxlan network
   - Test connectivity between instances

4. **Begin Phase 1 documentation**
   - Create `docs/operations/` directory
   - Write VM lifecycle procedures
   - Document emergency contacts and escalation

### Within 1 Week
5. Assign personnel to each phase
6. Set up sprint tracking (GitHub Projects, Jira, or similar)
7. Schedule sprint planning meetings
8. Establish daily standup recurring meeting

### Within 2 Weeks
9. Complete Phase 1 testing and documentation
10. Review Phase 1 deliverables
11. Plan Phase 2 in detail (monitoring stack selection)
12. Begin Phase 2 implementation

---

## Appendix: Command Reference

### Quick Start Commands
```bash
# Navigate to project
cd /Users/franksimpson/Desktop/hosted-cloud-scaleway

# Source environment secrets
source .secret

# SSH to frontend
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100

# SSH to worker
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.109.233

# Check deployment status
tail -f /tmp/opennebula_deployment.log

# Run validation
make validation

# Apply Scaleway drivers (if not done)
make specifics
```

### OpenNebula Commands (via SSH)
```bash
# Connect to frontend
ssh ubuntu@51.159.107.100

# Check OpenNebula version
onehost show

# List virtual machines
onevm list

# List virtual networks
onevnet list

# View daemon status
sudo systemctl status opennebula
sudo systemctl status opennebula-gate
sudo systemctl status opennebula-flow
sudo systemctl status opennebula-fireedge

# View logs
sudo tail -f /var/log/one/oned.log
sudo tail -f /var/log/one/gate.log
```

---

**Document Version**: 1.0
**Status**: APPROVED FOR IMPLEMENTATION
**Last Updated**: November 10, 2025
**Next Review**: December 10, 2025
