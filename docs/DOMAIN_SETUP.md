# Scaleway Domain Configuration & Setup

**Last Updated**: November 10, 2025
**Domain**: collectivnexus.com

## Overview

This document covers the complete domain setup for the OpenNebula infrastructure on Scaleway, including DNS configuration, SSL/TLS certificates, and reverse proxy setup.

---

## Table of Contents

1. [Domain Information](#domain-information)
2. [DNS Configuration](#dns-configuration)
3. [SSL/TLS Certificates](#ssltls-certificates)
4. [Reverse Proxy Setup](#reverse-proxy-setup)
5. [Service URLs](#service-urls)
6. [Deployment Steps](#deployment-steps)

---

## Domain Information

### Scaleway Domain Details
```
Domain Name:        collectivnexus.com
Registrar:          Scaleway
Status:             Active
Organization ID:    c5d299b8-8462-40fb-b5ae-32a8808bf394
Project ID:         93cee4fb-02ea-4951-a2a3-573885f04a98
Expiration:         November 7, 2026
DNS Servers:        ns0.dom.scw.cloud, ns1.dom.scw.cloud
DNSSEC Status:      disabled
```

---

## DNS Configuration

### DNS Records Created

All A records are pointing to the frontend node with TTL of 3600 seconds.

| Subdomain | IP Address | Purpose | Record ID |
|-----------|-----------|---------|-----------|
| opennebula.collectivnexus.com | 51.159.107.100 | OpenNebula Frontend | 22b2d25b-df67-4d40-a607-b08c45c80059 |
| fireedge.collectivnexus.com | 51.159.107.100 | FireEdge UI (HTTP 8080 → HTTPS 8080) | 16906964-980f-4e99-9867-bb4b9fae305f |
| onegate.collectivnexus.com | 51.159.107.100 | OneGate API (HTTP 5030 → HTTPS 5030) | d593e612-0c62-4844-9583-6d716fc4d744 |
| oneflow.collectivnexus.com | 51.159.107.100 | OneFlow API (HTTP 2434 → HTTPS 2434) | 9c8b6d15-4a21-4ef1-b673-0a2f135a7d49 |
| prometheus.collectivnexus.com | 51.159.107.100 | Prometheus Metrics | 5f1b7797-a9d2-43b9-b743-d6babdcf5627 |
| grafana.collectivnexus.com | 51.159.107.100 | Grafana Dashboards | e6dd719a-62ca-431d-9004-d2c55b39310f |
| fe.collectivnexus.com | 51.159.107.100 | Frontend Node Hostname | f36db531-e406-408f-870f-7c573eb9e900 |
| host01.collectivnexus.com | 51.159.109.233 | Worker Node 1 Hostname | f5c3a2e9-6b41-43b0-a199-1f6f26c91f4f |

### DNS API Details
```bash
# Query domain
curl -s -H "X-Auth-Token: $SCW_SECRET_KEY" \
  "https://api.scaleway.com/domain/v2beta1/domains"

# Query DNS records
curl -s -H "X-Auth-Token: $SCW_SECRET_KEY" \
  "https://api.scaleway.com/domain/v2beta1/dns-zones/collectivnexus.com/records"
```

### DNS Propagation
- Expected propagation time: 24-48 hours
- Status: Check with `nslookup` or `dig`
- Verify with: `nslookup opennebula.collectivnexus.com`

---

## SSL/TLS Certificates

### Certificate Strategy

We use **Let's Encrypt** with Certbot for free, automated HTTPS certificates:

```bash
# Install Certbot on frontend node
ssh -i scw/003.opennebula_instances/opennebula.pem ubuntu@51.159.107.100
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx python3-certbot-dns-scaleway

# Configure Scaleway DNS plugin (optional, for DNS validation)
# OR use HTTP validation (requires nginx already configured)
```

### Certificate Generation

For each subdomain:

```bash
# For single domain
sudo certbot certonly \
  --nginx \
  -d fireedge.collectivnexus.com \
  --agree-tos \
  --email admin@collectivnexus.com \
  --non-interactive

# For multiple domains (wildcard not recommended without additional zone)
sudo certbot certonly \
  --nginx \
  -d fireedge.collectivnexus.com \
  -d onegate.collectivnexus.com \
  -d oneflow.collectivnexus.com \
  -d prometheus.collectivnexus.com \
  -d grafana.collectivnexus.com \
  --agree-tos \
  --email admin@collectivnexus.com \
  --non-interactive
```

### Certificate Locations
```
/etc/letsencrypt/live/fireedge.collectivnexus.com/
├── cert.pem           (Public certificate)
├── chain.pem          (Intermediate certs)
├── fullchain.pem      (Full chain for nginx)
└── privkey.pem        (Private key)
```

### Certificate Auto-Renewal
```bash
# Certbot auto-renewal via systemd timer
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Manual renewal
sudo certbot renew --dry-run
sudo certbot renew
```

---

## Reverse Proxy Setup

### Nginx Installation & Configuration

#### 1. Install Nginx
```bash
ssh ubuntu@51.159.107.100
sudo apt-get update
sudo apt-get install -y nginx
```

#### 2. Nginx Configuration Files

**Main configuration**: `/etc/nginx/sites-available/opennebula-services`

```nginx
# FireEdge
upstream fireedge_backend {
    server localhost:8080;
}

server {
    listen 80;
    server_name fireedge.collectivnexus.com;

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name fireedge.collectivnexus.com;

    ssl_certificate /etc/letsencrypt/live/fireedge.collectivnexus.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/fireedge.collectivnexus.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass https://fireedge_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }
}

# OneGate
upstream onegate_backend {
    server localhost:5030;
}

server {
    listen 80;
    server_name onegate.collectivnexus.com;

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name onegate.collectivnexus.com;

    ssl_certificate /etc/letsencrypt/live/onegate.collectivnexus.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/onegate.collectivnexus.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass https://onegate_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
    }
}

# Grafana
upstream grafana_backend {
    server localhost:3000;
}

server {
    listen 80;
    server_name grafana.collectivnexus.com;

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name grafana.collectivnexus.com;

    ssl_certificate /etc/letsencrypt/live/grafana.collectivnexus.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/grafana.collectivnexus.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://grafana_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Prometheus
upstream prometheus_backend {
    server localhost:9090;
}

server {
    listen 80;
    server_name prometheus.collectivnexus.com;

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name prometheus.collectivnexus.com;

    ssl_certificate /etc/letsencrypt/live/prometheus.collectivnexus.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/prometheus.collectivnexus.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://prometheus_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### 3. Enable Configuration
```bash
sudo ln -s /etc/nginx/sites-available/opennebula-services \
  /etc/nginx/sites-enabled/opennebula-services

# Test configuration
sudo nginx -t

# Restart nginx
sudo systemctl restart nginx
```

---

## Service URLs

### Public Domain-Based URLs

| Service | URL | Purpose |
|---------|-----|---------|
| FireEdge UI | https://fireedge.collectivnexus.com | Web UI for VM management |
| OneGate | https://onegate.collectivnexus.com | VMs self-service API |
| OneFlow | https://oneflow.collectivnexus.com | Workflow automation |
| Grafana | https://grafana.collectivnexus.com | Monitoring dashboards |
| Prometheus | https://prometheus.collectivnexus.com | Metrics database |

### Backend Internal URLs (via SSH tunnel)

```bash
# SSH tunnel for direct access (alternative)
ssh -i scw/003.opennebula_instances/opennebula.pem \
  -L 8080:localhost:8080 \
  -L 5030:localhost:5030 \
  -L 3000:localhost:3000 \
  -L 9090:localhost:9090 \
  ubuntu@51.159.107.100
```

---

## Deployment Steps

### Phase 1: DNS Verification (Current)
- [x] Domain identified: collectivnexus.com
- [x] DNS records created via Scaleway API
- [ ] Wait 24-48 hours for DNS propagation
- [ ] Verify with: `nslookup opennebula.collectivnexus.com`

### Phase 2: SSL Certificate Setup (Next)
1. SSH to frontend: `ssh ubuntu@51.159.107.100`
2. Install Certbot and dependencies
3. Generate certificates for each domain
4. Automate renewal with systemd timer

### Phase 3: Reverse Proxy (After certs ready)
1. Install nginx on frontend
2. Create configuration (content provided above)
3. Validate configuration
4. Enable and restart nginx

### Phase 4: Service Configuration
1. Update OpenNebula services to use domain names
2. Update Grafana datasources to use domain URLs
3. Update monitoring configurations

### Phase 5: Documentation & Testing
1. Update ACCESS_GUIDE.md with domain URLs
2. Test all services via domain-based access
3. Verify SSL certificates
4. Test from external network

---

## Troubleshooting

### DNS Not Resolving
```bash
# Check DNS propagation globally
# https://mxtoolbox.com/

# Local check with specific nameserver
nslookup opennebula.collectivnexus.com ns0.dom.scw.cloud

# Flush local DNS (macOS)
sudo dscacheutil -flushcache
```

### Certificate Issues
```bash
# Check certificate validity
sudo certbot certificates

# View certificate details
openssl x509 -in /etc/letsencrypt/live/fireedge.collectivnexus.com/cert.pem -text -noout

# Manual renewal with verbose output
sudo certbot renew --verbose --dry-run
```

### Nginx Issues
```bash
# Check syntax
sudo nginx -t

# View error logs
sudo tail -f /var/log/nginx/error.log

# Check if port 80/443 are available
sudo ss -tlnp | grep -E ':(80|443)'
```

### Proxy Not Working
```bash
# Check nginx upstream
sudo netstat -tlnp | grep nginx

# Test backend connectivity
curl -k https://localhost:8080  # FireEdge
curl -k https://localhost:5030  # OneGate
curl http://localhost:3000      # Grafana
curl http://localhost:9090      # Prometheus
```

---

## Security Considerations

### Best Practices
- [ ] Use strong HTTPS ciphers (done in nginx config)
- [ ] Enable HSTS for production
- [ ] Restrict access by IP whitelist if needed
- [ ] Monitor certificate expiration
- [ ] Regular security audits of reverse proxy
- [ ] Enable firewall rules for HTTP/HTTPS only

### HSTS Configuration (Optional)
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### IP Whitelist Example
```nginx
location / {
    allow 10.0.0.0/8;      # Internal network
    allow 203.0.113.0/24;  # Partner network
    deny all;
}
```

---

## Monitoring & Maintenance

### Certificate Expiration Monitoring
```bash
# Check upcoming renewals
sudo certbot certificates

# Manual renewal (run monthly or as part of automation)
sudo certbot renew
```

### Log Rotation
```bash
# Nginx logs rotation - usually automatic
/var/log/nginx/access.log
/var/log/nginx/error.log
```

### DNS Health Check Script
```bash
#!/bin/bash
for domain in opennebula fireedge onegate oneflow prometheus grafana fe host01; do
  echo "Checking $domain.collectivnexus.com..."
  nslookup $domain.collectivnexus.com
done
```

---

## Related Documentation

- [ACCESS_GUIDE.md](./ACCESS_GUIDE.md) - Updated with domain-based URLs
- [NETWORK_TOPOLOGY.md](./architecture/NETWORK_TOPOLOGY.md) - Network architecture
- [MONITORING_SETUP.md](./operations/MONITORING_SETUP.md) - Monitoring stack
- [PROJECT_PLAN.md](../PROJECT_PLAN.md) - 6-month roadmap

---

**Document Version**: 1.0
**Created**: November 10, 2025
**Status**: DNS & Configuration ready for deployment
**Next Steps**: Execute Phase 2 (SSL certificates) once DNS propagates

⚠️ Keep this document updated as the domain configuration evolves.
