# OpenNebula Backup & Recovery Strategy

**Last Updated**: November 10, 2025
**Scope**: Full OpenNebula Platform Backup
**Target RTO**: < 1 hour | **Target RPO**: < 15 minutes

## Executive Summary

This document defines the backup and disaster recovery strategy for the OpenNebula hosted cloud platform on Scaleway. It covers:

- **RTO (Recovery Time Objective)**: < 1 hour to restore full platform
- **RPO (Recovery Point Objective)**: < 15 minutes of data loss acceptable
- **Backup Frequency**: Continuous for databases, daily for VM images
- **Retention Policy**: Daily (7 days), Weekly (4 weeks), Monthly (12 months)

---

## Critical Components to Backup

### 1. OpenNebula Database (MariaDB)
**Priority**: CRITICAL | **Frequency**: Continuous replication + Daily snapshots

The MariaDB database stores all OpenNebula state:
- VM configurations and metadata
- Network definitions
- User/group information
- ACL policies
- Quotas and resource limits

**Backup Method**: Binary log replication + nightly dumps

### 2. VM Disk Images
**Priority**: HIGH | **Frequency**: On-demand + Daily snapshots

All VM logical disks are stored in `/var/lib/one/datastores/`

**Backup Method**: Image snapshots + tiered storage (hot/warm/cold)

### 3. Configuration Files
**Priority**: MEDIUM | **Frequency**: Continuous (Infrastructure as Code)

Critical configuration:
- `/etc/one/` - OpenNebula config
- Ansible playbooks
- Terraform state
- Network configuration

**Backup Method**: Git version control (Infrastructure as Code)

### 4. Secrets & Credentials
**Priority**: CRITICAL | **Frequency**: As changed, encrypted

Sensitive data:
- API tokens
- Database passwords
- SSH keys
- Scaleway credentials

**Backup Method**: Encrypted vault, airgapped storage

---

## Backup Architecture

```
┌─────────────────────────────────────────────────────────┐
│         OpenNebula Frontend (fe)                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────────────────────────────┐       │
│  │  MariaDB (oned database)                     │       │
│  │  ├─ Binary logs (continuous)                 │───┐   │
│  │  └─ Nightly dumps                            │   │   │
│  └──────────────────────────────────────────────┘   │   │
│                                                      │   │
│  ┌──────────────────────────────────────────────┐   │   │
│  │  Datastore (/var/lib/one/datastores/)        │   │   │
│  │  ├─ VM images (QCOW2)                        │───┤   │
│  │  └─ Image snapshots                          │   │   │
│  └──────────────────────────────────────────────┘   │   │
│                                                      │   │
│  ┌──────────────────────────────────────────────┐   │   │
│  │  Configuration                               │   │   │
│  │  ├─ /etc/one/ directory                      │───┤   │
│  │  └─ Network config (netplan)                 │   │   │
│  └──────────────────────────────────────────────┘   │   │
│                                                      │   │
└──────────────────────────────────────────────────────┼───┘
                                                       │
                ┌──────────────────────────────────────┘
                │
                ▼
        ┌──────────────────┐
        │ Backup Storage   │
        ├──────────────────┤
        │• S3 (Scaleway)   │
        │• NFS Mount       │
        │• Local Snapshot  │
        │• Encrypted Vault │
        └──────────────────┘
```

---

## Backup Procedures

### Database Backup (MariaDB)

#### Daily Snapshot Backup
```bash
SSH_HOST="ubuntu@51.159.107.100"
SSH_KEY="scw/003.opennebula_instances/opennebula.pem"

# Run daily backup (schedule in cron)
ssh -i $SSH_KEY $SSH_HOST <<'EOF'
#!/bin/bash

# Create timestamped backup
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/one_backups"
mkdir -p $BACKUP_DIR

# Dump database
sudo mysqldump -u one -p$(cat ~/.one/one_auth | grep -oP 'pass:\K[^:]*') \
  --single-transaction \
  --lock-tables=false \
  --events \
  --routines \
  --triggers \
  opennebula > $BACKUP_DIR/opennebula_$BACKUP_DATE.sql

# Compress backup
gzip $BACKUP_DIR/opennebula_$BACKUP_DATE.sql

# Upload to S3 (if configured)
# aws s3 cp $BACKUP_DIR/opennebula_$BACKUP_DATE.sql.gz \
#   s3://backup-bucket/opennebula/

echo "Database backup completed: $BACKUP_DIR/opennebula_$BACKUP_DATE.sql.gz"
EOF
```

**Cron Schedule**:
```bash
# Daily at 2 AM UTC (11 PM CST)
0 2 * * * /home/ubuntu/backup_database.sh >> /var/log/one_backup.log 2>&1
```

#### Database Restore Procedure
```bash
# 1. Stop OpenNebula daemon
ssh $SSH_HOST "sudo systemctl stop opennebula opennebula-gate opennebula-flow opennebula-fireedge"

# 2. Restore database from backup
BACKUP_FILE="opennebula_20251110_020000.sql.gz"
ssh $SSH_HOST <<EOF
gunzip -c /tmp/one_backups/$BACKUP_FILE | mysql -u one -p opennebula
EOF

# 3. Verify database
ssh $SSH_HOST "mysql -u one -p -e 'SELECT COUNT(*) FROM opennebula.vm_pool;'"

# 4. Restart OpenNebula
ssh $SSH_HOST "sudo systemctl start opennebula opennebula-gate opennebula-flow opennebula-fireedge"

# 5. Verify connectivity
ssh $SSH_HOST "onehost list"
```

---

### VM Image Backup

#### Create Image Snapshot
```bash
SSH_HOST="ubuntu@51.159.107.100"

ssh -i scw/003.opennebula_instances/opennebula.pem $SSH_HOST <<'EOF'
export ONE_AUTH=~oneadmin/.one/one_auth
export ONE_XMLRPC=http://localhost:2633/RPC2

# Get list of all images
oneimage list

# Create snapshot for each image
oneimage snapshot-create <IMAGE_ID> "backup-$(date +%Y%m%d)"

# Verify snapshot created
oneimage snapshot-list <IMAGE_ID>
EOF
```

#### Backup Image to S3
```bash
# Configuration for S3 backup
S3_BUCKET="my-opennebula-backups"
S3_REGION="fr-par"

ssh $SSH_HOST <<'EOF'
#!/bin/bash

# Get all QCOW2 images
IMAGES_DIR="/var/lib/one/datastores/0"

for IMAGE in $(ls $IMAGES_DIR/*.qcow2 2>/dev/null); do
  IMAGE_NAME=$(basename $IMAGE)
  echo "Backing up $IMAGE_NAME to S3..."

  # Upload to S3
  aws s3 cp $IMAGE \
    s3://$S3_BUCKET/images/$IMAGE_NAME \
    --storage-class STANDARD_IA \
    --sse AES256

  if [ $? -eq 0 ]; then
    echo "✓ Backup successful: $IMAGE_NAME"
  else
    echo "✗ Backup failed: $IMAGE_NAME"
  fi
done
EOF
```

---

### Configuration Backup (Infrastructure as Code)

All infrastructure code is version-controlled in Git:

```bash
# Current project repo
cd /Users/franksimpson/Desktop/hosted-cloud-scaleway

# Backup entire infrastructure (already in git)
git log --oneline | head -20

# Push to remote (automated)
git push origin main
```

**Files backed up**:
- `scw/*/` - Terraform modules
- `playbooks/` - Ansible playbooks
- `roles/` - Custom roles
- `PROJECT_PLAN.md` - Project documentation
- `DEPLOYMENT_CONTEXT.md` - Deployment notes

**Backup Strategy**: Continuous push to GitHub (public repo with automated backups)

---

## Retention Policy

| Item | Frequency | Daily | Weekly | Monthly | Yearly |
|------|-----------|-------|--------|---------|--------|
| Database dumps | Once daily | 7 days | 4 weeks | 12 months | N/A |
| VM snapshots | On-demand | 3 days | 2 weeks | 90 days | N/A |
| Config backup | Continuous | N/A | N/A | N/A | Permanent |

### Cleanup Script
```bash
#!/bin/bash
# Run weekly to clean old backups

BACKUP_DIR="/tmp/one_backups"
S3_BUCKET="my-opennebula-backups"

# Delete local backups older than 7 days
find $BACKUP_DIR -name "opennebula_*.sql.gz" -mtime +7 -delete

# Archive old S3 backups to Glacier
aws s3 sync s3://$S3_BUCKET/images/ \
  --exclude "*" \
  --include "*.qcow2" \
  --source region fr-par \
  --destination s3://archive-bucket/images/ \
  --storage-class GLACIER

echo "Backup cleanup completed"
```

---

## Disaster Recovery Plan

### Scenario 1: Single VM Loss

**Time to Recover**: 10-15 minutes

```bash
# 1. Restore VM from snapshot
onevm snapshot-revert <VM_ID> <SNAPSHOT_ID>

# 2. Or restore from S3 backup
aws s3 cp s3://backups/vm-images/vm-001.qcow2 \
  /var/lib/one/datastores/0/

# 3. Re-register image in OpenNebula
oneimage create --datastore 0 -n "vm-001-restored" /var/lib/one/datastores/0/vm-001.qcow2

# 4. Create new VM from restored image
onetemplate create --from-image <IMAGE_ID>
```

### Scenario 2: Database Corruption

**Time to Recover**: 20-30 minutes

```bash
# 1. Stop all OpenNebula services
ssh ubuntu@51.159.107.100 "sudo systemctl stop opennebula-*"

# 2. Find latest good backup
ls -lrt /tmp/one_backups/opennebula_*.sql.gz | tail -5

# 3. Restore database
gunzip -c /tmp/one_backups/opennebula_20251110_020000.sql.gz | \
  mysql -u one -p opennebula

# 4. Verify data integrity
mysql -u one -p -e "SELECT COUNT(*) FROM opennebula.vm_pool;"

# 5. Restart OpenNebula
ssh ubuntu@51.159.107.100 "sudo systemctl start opennebula opennebula-gate opennebula-flow"

# 6. Verify API responding
onehost list
```

### Scenario 3: Complete Site Failure

**Time to Recover**: 1-2 hours

**Prerequisites**:
- Backup site with prepared infrastructure
- Secondary datacenter (Scaleway Paris-3 zone)
- Database backup in S3
- VM images in S3

**Recovery Steps**:
```bash
# 1. Deploy to secondary site (via Terraform)
cd scw/
make deploy-region=fr-par-3

# 2. Wait for infrastructure provisioning (~20 min)
terraform apply -auto-approve

# 3. Deploy OpenNebula to new infrastructure
make deployment

# 4. Restore database from S3 backup
aws s3 cp s3://backups/opennebula_latest.sql.gz - | \
  gunzip | mysql -u one -p opennebula

# 5. Restore VM images from S3
aws s3 sync s3://backups/images/ \
  /var/lib/one/datastores/0/ \
  --exclude "*" \
  --include "*.qcow2"

# 6. Re-register images in OpenNebula
for IMG in /var/lib/one/datastores/0/*.qcow2; do
  oneimage create --datastore 0 -n "$(basename $IMG .qcow2)" $IMG
done

# 7. Verify VM count matches
onevm list
```

---

## Backup Testing & Validation

### Daily Validation
```bash
#!/bin/bash
# Scheduled daily at 3 AM

function validate_backup() {
  BACKUP_FILE=$1

  # Check file size (should be > 1MB)
  SIZE=$(stat -f%z $BACKUP_FILE)
  if [ $SIZE -lt 1000000 ]; then
    echo "ERROR: Backup file too small: $BACKUP_FILE"
    return 1
  fi

  # Test restore to temporary database
  TEMP_DB="opennebula_test_$(date +%s)"
  mysql -u one -p -e "CREATE DATABASE $TEMP_DB;"
  gunzip -c $BACKUP_FILE | mysql -u one -p $TEMP_DB

  # Verify table count
  TABLE_COUNT=$(mysql -u one -p -e "USE $TEMP_DB; SHOW TABLES;" | wc -l)
  if [ $TABLE_COUNT -lt 20 ]; then
    echo "ERROR: Insufficient tables in backup: $TABLE_COUNT"
    mysql -u one -p -e "DROP DATABASE $TEMP_DB;"
    return 1
  fi

  # Clean up
  mysql -u one -p -e "DROP DATABASE $TEMP_DB;"

  echo "✓ Backup validation successful: $BACKUP_FILE"
  return 0
}

LATEST=$(ls -t /tmp/one_backups/opennebula_*.sql.gz | head -1)
validate_backup $LATEST
```

### Monthly Restore Drill
Schedule quarterly full restore tests:

```bash
# 1. Request maintenance window (off-peak)
# 2. Document pre-restore state
onevm list > /tmp/vms_before.txt
onevnet list > /tmp/nets_before.txt

# 3. Perform full restore
# (See "Scenario 2: Database Corruption" above)

# 4. Validate restored state
onevm list > /tmp/vms_after.txt
diff /tmp/vms_before.txt /tmp/vms_after.txt

# 5. Test VM access
for VM_ID in $(onevm list -f ID | tail -n +2); do
  onevm show $VM_ID | grep -q "RUNNING" && echo "VM $VM_ID: OK"
done

# 6. Document results and lessons learned
```

---

## Backup Monitoring & Alerts

### Key Metrics to Monitor
```
- Last successful backup timestamp
- Backup size (detect anomalies)
- Backup duration (detect performance degradation)
- Number of failed backup attempts
- S3 upload success rate
- Database consistency check results
```

### Alert Thresholds
- **No backup in 24 hours**: CRITICAL
- **Backup size < 10MB**: WARNING
- **Backup duration > 1 hour**: WARNING
- **S3 upload failure**: CRITICAL
- **Database consistency errors**: CRITICAL

### Prometheus Metrics
```yaml
# Add to prometheus.yml
- job_name: 'opennebula_backups'
  static_configs:
    - targets: ['51.159.107.100:9100']
  metrics_path: '/metrics/backups'
  scrape_interval: 5m
```

---

## Disaster Recovery Contacts & Escalation

| Severity | Contact | Response Time | Escalation |
|----------|---------|----------------|-----------|
| Critical (No backups in 24h) | Primary DevOps | 15 min | CTO |
| Database corruption | DevOps + DBA | 30 min | Infrastructure Lead |
| Complete site loss | Full team | Immediate | VP Operations |

### Contact Information
```
Primary DevOps: <email/phone>
Secondary DevOps: <email/phone>
Database Administrator: <email/phone>
Infrastructure Lead: <email/phone>
VP Operations: <email/phone>
Scaleway Support: https://console.scaleway.com/support
```

---

## Compliance & Audit

### Backup Verification Checklist
- [ ] Daily backups completed successfully
- [ ] Backup files transferred to S3
- [ ] Backup integrity verified (test restore)
- [ ] Backup logs reviewed for errors
- [ ] Retention policy enforced
- [ ] Access logs audited

### Audit Reports
Generate monthly:
```bash
# Backup success rate
grep "Backup" /var/log/one_backup.log | \
  grep -c "completed" / grep -c "error" | \
  awk '{ print "Success Rate: " ($1/($1+$2))*100 "%"}'

# Latest backup timestamp
ls -1 /tmp/one_backups/opennebula_*.sql.gz | \
  tail -1 | xargs stat -f "Last backup: %Sm"

# Total backup size
du -sh /tmp/one_backups/
du -sh /var/lib/one/datastores/
```

---

## Related Documents

- [VM Lifecycle Procedures](./VM_LIFECYCLE.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Network Management](./NETWORK_MANAGEMENT.md)
- [PROJECT_PLAN.md](../PROJECT_PLAN.md)

---

**Document Version**: 1.0
**Status**: APPROVED FOR IMPLEMENTATION
**Last Updated**: November 10, 2025
**Next Review**: November 17, 2025
