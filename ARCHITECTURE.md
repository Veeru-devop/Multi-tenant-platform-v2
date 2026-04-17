# Architecture — WordPress Multitenancy Platform

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HOST MACHINE                                    │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                        FRONTEND NETWORK                                │  │
│  │                        (wp-frontend)                                   │  │
│  │                                                                        │  │
│  │    ┌──────────────────────────────────────┐                           │  │
│  │    │         NGINX REVERSE PROXY          │                           │  │
│  │    │         Container: wp-nginx          │                           │  │
│  │    │                                      │                           │  │
│  │    │  :80  → HTTP traffic                 │                           │  │
│  │    │  :8080 → stub_status (metrics)       │                           │  │
│  │    │                                      │                           │  │
│  │    │  Routes by Host header:              │                           │  │
│  │    │  tenant-alpha.localhost → wp-alpha    │                           │  │
│  │    │  tenant-beta.localhost  → wp-beta     │                           │  │
│  │    └──────────┬───────────────┬────────────┘                           │  │
│  │               │               │                                        │  │
│  │    ┌──────────▼────────┐  ┌──▼────────────────┐                       │  │
│  │    │  WORDPRESS ALPHA  │  │  WORDPRESS BETA    │                       │  │
│  │    │  wp-alpha          │  │  wp-beta            │                       │  │
│  │    │  PHP 8.2 + Apache  │  │  PHP 8.2 + Apache  │                       │  │
│  │    └──────────┬────────┘  └──┬────────────────┘                       │  │
│  └───────────────┼──────────────┼────────────────────────────────────────┘  │
│                  │              │                                            │
│  ┌───────────────▼──────┐  ┌───▼──────────────────┐                        │
│  │  BACKEND-ALPHA       │  │  BACKEND-BETA         │                        │
│  │  (internal network)  │  │  (internal network)   │                        │
│  │                      │  │                        │                        │
│  │  ┌────────────────┐  │  │  ┌────────────────┐   │                        │
│  │  │  MariaDB 11.2  │  │  │  │  MariaDB 11.2  │   │                        │
│  │  │  db-alpha      │  │  │  │  db-beta       │   │                        │
│  │  │  wp_alpha DB   │  │  │  │  wp_beta DB    │   │                        │
│  │  └────────────────┘  │  │  └────────────────┘   │                        │
│  └──────────────────────┘  └────────────────────────┘                        │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                      MONITORING NETWORK                                │  │
│  │                      (wp-monitoring)                                   │  │
│  │                                                                        │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐              │  │
│  │  │Prometheus│  │  Grafana │  │   Loki   │  │ Promtail │              │  │
│  │  │  :9090   │  │  :3000   │  │  :3100   │  │ (agent)  │              │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘              │  │
│  │                                                                        │  │
│  │  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ cAdvisor │  │MySQL Export-α │  │MySQL Export-β │  │Nginx Exporter│  │  │
│  │  │  :8081   │  │  (internal)   │  │  (internal)   │  │  (internal)  │  │  │
│  │  └──────────┘  └──────────────┘  └──────────────┘  └──────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### Reverse Proxy Layer (Nginx)

| Aspect | Detail |
|--------|--------|
| Image | `nginx:1.25-alpine` |
| Purpose | Route traffic to correct tenant, SSL termination, rate limiting |
| Security | X-Frame-Options, X-Content-Type-Options, XML-RPC blocking |
| Rate Limits | `wp-login.php`: 5 req/s, General: 30 req/s |

### WordPress Containers

| Aspect | Detail |
|--------|--------|
| Image | `wordpress:6-php8.2-apache` |
| Hardening | `DISALLOW_FILE_EDIT`, `WP_AUTO_UPDATE_CORE=false` |
| Health Check | Polls `/wp-admin/install.php` every 30s |
| Volumes | Separate `data` and `uploads` volumes per tenant |

### Database Containers

| Aspect | Detail |
|--------|--------|
| Image | `mariadb:11.2` |
| Network | Internal-only (`internal: true`) — no external access |
| Health Check | Built-in `healthcheck.sh --connect --innodb_initialized` |
| Isolation | Each tenant has its own MariaDB instance and volume |

## Network Topology

```
wp-frontend (bridge)
├── nginx
├── wp-alpha
└── wp-beta

wp-backend-alpha (bridge, internal)
├── wp-alpha
├── db-alpha
└── mysqld-exporter-alpha

wp-backend-beta (bridge, internal)
├── wp-beta
├── db-beta
└── mysqld-exporter-beta

wp-monitoring (bridge)
├── prometheus
├── grafana
├── loki
├── promtail
├── cadvisor
├── nginx-exporter
├── mysqld-exporter-alpha
└── mysqld-exporter-beta
```

### Why This Network Design?

1. **Backend networks are `internal: true`** — databases cannot be reached from outside Docker
2. **MySQL exporters bridge monitoring ↔ backend** — they can scrape DB metrics while remaining on the monitoring network
3. **Frontend is shared** — only Nginx and WordPress containers communicate here
4. **No cross-tenant backend access** — wp-alpha cannot reach db-beta

## Data Flow

### Request Flow
```
User Browser
  → DNS: tenant-alpha.localhost → 127.0.0.1
    → Nginx (:80)
      → Host header match: tenant-alpha.localhost
        → Upstream: wp-alpha:80
          → PHP-FPM processes WordPress
            → MariaDB (db-alpha:3306) via backend-alpha network
```

### Metrics Flow
```
cAdvisor → scrapes Docker API → exposes container metrics
mysqld-exporter → connects to MariaDB → exposes DB metrics
nginx-exporter → scrapes /stub_status → exposes proxy metrics
  ↓
Prometheus → scrapes all exporters every 15s
  ↓
Grafana → queries Prometheus → renders dashboards
```

### Logs Flow
```
WordPress/Nginx/MariaDB → Docker stdout/stderr
  ↓
Promtail → Docker socket discovery → reads container logs
  → Adds labels: container, tenant, service_type
    ↓
Loki → stores indexed logs
  ↓
Grafana → queries Loki → displays in log panel
```

## Volume Map

| Volume | Container | Mount Point | Purpose |
|--------|-----------|-------------|---------|
| `wp_alpha_data` | wp-alpha | `/var/www/html` | WordPress core files |
| `wp_alpha_uploads` | wp-alpha | `/var/www/html/wp-content/uploads` | Tenant A media |
| `db_alpha_data` | db-alpha | `/var/lib/mysql` | Tenant A database |
| `wp_beta_data` | wp-beta | `/var/www/html` | WordPress core files |
| `wp_beta_uploads` | wp-beta | `/var/www/html/wp-content/uploads` | Tenant B media |
| `db_beta_data` | db-beta | `/var/lib/mysql` | Tenant B database |
| `nginx_logs` | nginx, promtail | `/var/log/nginx` | Shared access log volume |
| `prometheus_data` | prometheus | `/prometheus` | Metrics time-series DB |
| `grafana_data` | grafana | `/var/lib/grafana` | Dashboard state |
| `loki_data` | loki | `/loki` | Log storage |

## Production Mapping

| Local Component | AWS Production Equivalent |
|----------------|--------------------------|
| Docker Compose | EC2 + ASG |
| Nginx container | ALB / Nginx on EC2 |
| MariaDB containers | Amazon RDS (Aurora MySQL) |
| Docker volumes | Amazon EFS / EBS |
| Prometheus + Grafana | Amazon CloudWatch + Grafana Cloud |
| Loki + Promtail | CloudWatch Logs / Datadog |
| GitHub Actions | Same (GitHub Actions) |
| `.env` files | AWS Secrets Manager / SSM Parameter Store |
