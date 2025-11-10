# OpenNebula Monitoring & Observability Setup Guide

**Last Updated**: November 10, 2025
**Scope**: Prometheus + Grafana monitoring stack
**Systems Monitored**: OpenNebula, MariaDB, Hosts, VMs

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Dashboards](#dashboards)
6. [Alerting](#alerting)
7. [Troubleshooting](#troubleshooting)

---

## Overview

### Monitoring Stack Components
- **Prometheus**: Time-series database and monitoring engine
- **Grafana**: Data visualization and alerting
- **Node Exporter**: Hardware and OS metrics
- **collectd**: OpenNebula metrics (already deployed)
- **MySQL Exporter**: Database metrics

### Key Metrics to Monitor

#### Host Metrics
```
- CPU utilization (per core, total)
- Memory usage (used, available, free)
- Disk I/O (read/write rates, queue depth)
- Network traffic (in/out, packets, errors)
- System load average
- Swap usage
```

#### OpenNebula Metrics
```
- Running VMs vs. total capacity
- API response time
- Scheduler queue length
- Hosts status (ENABLED, DISABLED, ERROR)
- Network creation/deletion rates
- Datastore capacity and utilization
```

#### Database Metrics
```
- Connection count
- Query execution time
- Replication lag (if applicable)
- Slow query count
- Cache hit ratio
```

#### VM Metrics
```
- CPU time per VM
- Memory usage per VM
- Disk I/O per VM
- Network traffic per VM
- VM creation/destruction rate
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Monitoring Stack                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────┐         │
│  │          Prometheus Server                 │         │
│  │  • Time-series database (TSDB)             │         │
│  │  • Scrapes metrics every 15s               │         │
│  │  • 15GB storage (14 days retention)        │         │
│  │  • Local storage on /var/lib/prometheus    │         │
│  └────────────────────────────────────────────┘         │
│                      ▲                                   │
│                      │ Pull metrics                      │
│    ┌─────────────────┼─────────────────┐               │
│    │                 │                 │               │
│  ┌─────────┐    ┌─────────┐    ┌──────────────┐        │
│  │  Node   │    │  MySQL  │    │  Prometheus  │        │
│  │ Exporter│    │ Exporter│    │  Pushgateway │        │
│  │ :9100  │    │ :9104   │    │    :9091     │        │
│  └─────────┘    └─────────┘    └──────────────┘        │
│     (fe,            (fe)          (for batch jobs)      │
│    host01)                                              │
│                                                          │
│  ┌────────────────────────────────────────────┐         │
│  │         Grafana Server                     │         │
│  │  • Data visualization                      │         │
│  │  • Custom dashboards                       │         │
│  │  • Alert rule engine                       │         │
│  │  • Web UI: https://51.159.107.100:3000   │         │
│  └────────────────────────────────────────────┘         │
│         (frontend node, Docker container)               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Installation

### Step 1: Install Prometheus

#### 1.1 Create Prometheus User
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
# Create prometheus user
sudo useradd --no-create-home --shell /bin/false prometheus

# Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus
EOF
```

#### 1.2 Download and Install Prometheus Binary
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
cd /tmp
curl -sL https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz | tar xz

sudo cp prometheus-2.48.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-2.48.0.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify installation
prometheus --version
EOF
```

#### 1.3 Configure Prometheus
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'PROMETHEUS'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'opennebula-scaleway'
    region: 'fr-par'

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files:
  - '/etc/prometheus/alert_rules.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'frontend'
    static_configs:
      - targets: ['fe:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'fe'

  - job_name: 'worker'
    static_configs:
      - targets: ['host01:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'host01'

  - job_name: 'mysql'
    static_configs:
      - targets: ['fe:9104']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'fe_mysql'

  - job_name: 'opennebula'
    honor_timestamps: true
    metrics_path: '/metrics'
    scheme: 'http'
    static_configs:
      - targets: ['fe:8000']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'opennebula_api'
PROMETHEUS

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
EOF
```

#### 1.4 Create Alert Rules
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
sudo tee /etc/prometheus/alert_rules.yml > /dev/null <<'ALERTS'
groups:
  - name: infrastructure_alerts
    interval: 30s
    rules:
      - alert: HostHighCPU
        expr: (1 - avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value | humanizePercentage }} on {{ $labels.instance }}"

      - alert: HostHighMemory
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | humanizePercentage }} on {{ $labels.instance }}"

      - alert: HostDiskPressure
        expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.lxcfs|squashfs|vfat"} / node_filesystem_size_bytes) < 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk pressure on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} disk space available on {{ $labels.device }}"

      - alert: HostOutOfMemory
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.95
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Out of memory on {{ $labels.instance }}"

      - alert: OpenNebulaDaemonDown
        expr: up{job="opennebula"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "OpenNebula daemon is down"
          description: "OpenNebula daemon has been unreachable for more than 2 minutes"

      - alert: MySQLReplicationLag
        expr: mysql_slave_status_seconds_behind_master > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MySQL replication lag detected"
          description: "MySQL replication is {{ $value }} seconds behind master"

      - alert: MySQLDown
        expr: up{job="mysql"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "MySQL database is down"
          description: "MySQL database has been unreachable for more than 2 minutes"
ALERTS

sudo chown prometheus:prometheus /etc/prometheus/alert_rules.yml
EOF
```

#### 1.5 Create Systemd Service
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'SERVICE'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=14d \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=:9090

Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
sudo systemctl status prometheus
EOF
```

---

### Step 2: Install Node Exporter

#### 2.1 Install on Frontend (fe)
```bash
ssh ubuntu@51.159.107.100 <<'EOF'
# Download and install
cd /tmp
curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz | tar xz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chown root:root /usr/local/bin/node_exporter

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'SERVICE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes

Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
EOF
```

#### 2.2 Install on Worker (host01)
```bash
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.109.233 <<'EOF'
# Same steps as above
cd /tmp
curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz | tar xz
sudo cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
sudo chown root:root /usr/local/bin/node_exporter

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'SERVICE'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes

Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
EOF
```

---

### Step 3: Install MySQL Exporter

```bash
ssh ubuntu@51.159.107.100 <<'EOF'
# Download and install
cd /tmp
curl -sL https://github.com/prometheus/mysqld_exporter/releases/download/v0.15.0/mysqld_exporter-0.15.0.linux-amd64.tar.gz | tar xz
sudo cp mysqld_exporter-0.15.0.linux-amd64/mysqld_exporter /usr/local/bin/
sudo chown root:root /usr/local/bin/mysqld_exporter

# Create MySQL user for exporter
mysql -u root -p <<'SQL'
CREATE USER 'prometheus'@'localhost' IDENTIFIED BY 'prometheus_password';
GRANT REPLICATION CLIENT, PROCESS ON *.* TO 'prometheus'@'localhost';
GRANT SELECT ON performance_schema.* TO 'prometheus'@'localhost';
FLUSH PRIVILEGES;
SQL

# Create exporter config
sudo mkdir -p /etc/mysql_exporter
sudo tee /etc/mysql_exporter/.my.cnf > /dev/null <<'CNFFILE'
[client]
user=prometheus
password=prometheus_password
CNFFILE

# Create systemd service
sudo tee /etc/systemd/system/mysql_exporter.service > /dev/null <<'SERVICE'
[Unit]
Description=MySQL Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/mysqld_exporter \
  --config.my-cnf=/etc/mysql_exporter/.my.cnf \
  --web.listen-address=:9104

Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable mysql_exporter
sudo systemctl start mysql_exporter
EOF
```

---

### Step 4: Install Grafana

```bash
ssh ubuntu@51.159.107.100 <<'EOF'
# Install Grafana via Docker
sudo docker run -d \
  --name grafana \
  --restart always \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_USERS_ALLOW_SIGN_UP=false \
  -v /var/lib/grafana:/var/lib/grafana \
  -v /etc/grafana/provisioning:/etc/grafana/provisioning \
  grafana/grafana:latest

# Wait for Grafana to start
sleep 10

# Verify
curl -s http://localhost:3000/api/health | jq .
EOF
```

---

## Configuration

### Grafana Data Source: Prometheus

```bash
ssh ubuntu@51.159.107.100 <<'EOF'
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }' \
  http://admin:admin@localhost:3000/api/datasources
EOF
```

### Grafana Provisioning

Create dashboard provisioning directory:

```bash
ssh ubuntu@51.159.107.100 <<'EOF'
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/provisioning/datasources

# Create datasource provisioning
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'DATASOURCE'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    url: http://localhost:9090
    isDefault: true
    editable: true
DATASOURCE

# Restart Grafana
sudo docker restart grafana
EOF
```

---

## Dashboards

### Pre-built Dashboards to Import

#### 1. Node Exporter Dashboard (ID: 1860)
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "Node Exporter Full",
      "uid": "node-exporter-full",
      "timezone": "browser",
      "panels": []
    },
    "overwrite": true
  }' \
  http://admin:admin@localhost:3000/api/dashboards/db
```

#### 2. MySQL Dashboard (ID: 7362)
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "MySQL Overview",
      "uid": "mysql-overview",
      "timezone": "browser",
      "panels": []
    },
    "overwrite": true
  }' \
  http://admin:admin@localhost:3000/api/dashboards/db
```

#### 3. Create Custom OpenNebula Dashboard

```yaml
{
  "dashboard": {
    "title": "OpenNebula Infrastructure",
    "uid": "opennebula-infra",
    "timezone": "browser",
    "panels": [
      {
        "title": "Host CPU Usage",
        "targets": [
          {
            "expr": "1 - avg by (instance) (irate(node_cpu_seconds_total{mode='idle'}[5m]))"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Host Memory Usage",
        "targets": [
          {
            "expr": "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Disk Space Available",
        "targets": [
          {
            "expr": "node_filesystem_avail_bytes{fstype!~\"tmpfs|fuse.lxcfs|squashfs|vfat\"}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Network Traffic",
        "targets": [
          {
            "expr": "irate(node_network_transmit_bytes_total[5m])"
          }
        ],
        "type": "graph"
      }
    ]
  },
  "overwrite": true
}
```

---

## Alerting

### Alertmanager Configuration

```bash
ssh ubuntu@51.159.107.100 <<'EOF'
# Install Alertmanager
cd /tmp
curl -sL https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz | tar xz
sudo cp alertmanager-0.26.0.linux-amd64/alertmanager /usr/local/bin/

# Create configuration
sudo mkdir -p /etc/alertmanager
sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<'ALERTMANAGER'
global:
  resolve_timeout: 5m

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      repeat_interval: 1h
    - match:
        severity: warning
      receiver: 'warning'
      repeat_interval: 4h

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5000/webhooks/default'

  - name: 'critical'
    webhook_configs:
      - url: 'http://localhost:5000/webhooks/critical'
    # Uncomment to add email
    # email_configs:
    #   - to: 'ops@example.com'
    #     from: 'alertmanager@example.com'
    #     smarthost: 'smtp.example.com:587'
    #     auth_username: 'user@example.com'
    #     auth_password: 'password'

  - name: 'warning'
    webhook_configs:
      - url: 'http://localhost:5000/webhooks/warning'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
ALERTMANAGER

sudo chown -R prometheus:prometheus /etc/alertmanager
EOF
```

### Create Systemd Service for Alertmanager

```bash
ssh ubuntu@51.159.107.100 <<'EOF'
sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<'SERVICE'
[Unit]
Description=Prometheus Alertmanager
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager \
  --web.listen-address=:9093

Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager
EOF
```

---

## Troubleshooting

### Prometheus not scraping metrics

**Check status**:
```bash
ssh ubuntu@51.159.107.100 "curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health==\"down\")'"
```

**Solution**:
- Verify exporters are running: `systemctl status node_exporter mysql_exporter`
- Check firewall rules allowing port access
- Verify network connectivity: `ping host01`
- Review Prometheus logs: `journalctl -u prometheus -f`

### Grafana not showing data

**Check datasource**:
```bash
curl -s http://admin:admin@localhost:3000/api/datasources | jq .
```

**Solutions**:
- Verify Prometheus is healthy: `curl http://localhost:9090/-/healthy`
- Check dashboard queries in detail
- Ensure metrics are being collected: `curl http://localhost:9090/api/v1/query?query=up`

### High memory usage in Prometheus

**Monitor storage usage**:
```bash
ssh ubuntu@51.159.107.100 "du -sh /var/lib/prometheus"
```

**Solutions**:
- Reduce retention time in `--storage.tsdb.retention.time` (default 14d)
- Lower scrape interval from 15s to 30s
- Set storage size limit with `--storage.tsdb.max-block-duration`

---

## Quick Access

- **Prometheus**: http://51.159.107.100:9090
- **Grafana**: http://51.159.107.100:3000 (admin/admin)
- **Alertmanager**: http://51.159.107.100:9093

---

**Document Version**: 1.0
**Last Updated**: November 10, 2025
**Next Review**: November 17, 2025
