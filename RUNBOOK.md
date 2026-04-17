# Operational Runbook — WordPress Multitenancy Platform

## Table of Contents

- [Quick Reference](#quick-reference)
- [Alert Response Procedures](#alert-response-procedures)
  - [WordPress Container Down](#wordpress-container-down)
  - [High Latency](#high-latency)
  - [Database Down](#database-down)
  - [High DB Connections](#high-db-connections)
  - [High Memory](#high-memory)
- [Common Operations](#common-operations)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Escalation Matrix](#escalation-matrix)

---

## Quick Reference

### Key URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Tenant Alpha | http://tenant-alpha.localhost | WP admin (set during install) |
| Tenant Beta | http://tenant-beta.localhost | WP admin (set during install) |
| Grafana | http://localhost:3000 | See `.env` (`GRAFANA_ADMIN_USER`) |
| Prometheus | http://localhost:9090 | No auth |

### Key Commands

```bash
# Check all services
make status

# View logs (all services)
make logs

# Restart everything
make restart

# Backup all tenants
make backup

# Open shell in WordPress container
make shell-alpha

# Open database CLI
make db-alpha
```

---

## Alert Response Procedures

### WordPress Container Down

**Alert**: `WordPressContainerDown`
**Severity**: 🔴 Critical
**Condition**: WordPress container not seen by cAdvisor for > 60 seconds

#### Diagnosis Steps

```bash
# 1. Check container status
docker ps -a --filter "name=wp-alpha"
docker ps -a --filter "name=wp-beta"

# 2. Check container logs
docker logs wp-alpha --tail 100
docker logs wp-beta --tail 100

# 3. Check container health
docker inspect --format='{{json .State.Health}}' wp-alpha | jq .

# 4. Check resource usage
docker stats --no-stream wp-alpha wp-beta
```

#### Resolution

| Cause | Fix |
|-------|-----|
| Container crashed (OOM) | `docker restart wp-alpha` — review memory limits |
| Database dependency failure | Fix DB first (see [Database Down](#database-down)), then restart WP |
| Configuration error | Check `docker logs wp-alpha` for PHP/Apache errors |
| Volume mount issue | `docker inspect wp-alpha` — verify volume mounts |
| Port conflict | Check `docker port wp-alpha` and host port usage |

```bash
# Quick fix: restart the container
docker restart wp-alpha

# If restart fails, recreate:
docker compose up -d wp-alpha

# Nuclear option: full restart
make restart
```

---

### High Latency

**Alert**: `NginxHighLatency`
**Severity**: 🟡 Warning
**Condition**: Average upstream response time > 2s for 5 minutes

#### Diagnosis Steps

```bash
# 1. Check Nginx status
docker exec wp-nginx nginx -t
curl -s http://localhost:8080/stub_status

# 2. Check upstream response times in logs
docker exec wp-nginx tail -100 /var/log/nginx/access.log | \
  awk '{print $NF}' | sort -n | tail -20

# 3. Check WordPress container resources
docker stats --no-stream wp-alpha wp-beta

# 4. Check database query performance
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SHOW PROCESSLIST;" 2>/dev/null

# 5. Check for slow queries
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null
```

#### Resolution

| Cause | Fix |
|-------|-----|
| WordPress PHP processing slow | Check for resource-heavy plugins; increase PHP memory |
| Database slow queries | Identify and optimize queries; add indexes |
| Insufficient container resources | Increase CPU/memory limits in compose file |
| High traffic load | Enable caching (Redis/Varnish); scale horizontally |

```bash
# Check for long-running DB queries
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SELECT * FROM information_schema.processlist WHERE TIME > 5;"

# Restart PHP (within WordPress container)
docker exec wp-alpha apachectl graceful
```

---

### Database Down

**Alert**: `MariaDBExporterDown`
**Severity**: 🔴 Critical
**Condition**: MySQL exporter unreachable for > 1 minute

#### Diagnosis Steps

```bash
# 1. Check database container
docker ps -a --filter "name=db-alpha"
docker logs db-alpha --tail 100

# 2. Test database connectivity
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SELECT 1;" 2>/dev/null

# 3. Check disk space (within container)
docker exec db-alpha df -h /var/lib/mysql

# 4. Check InnoDB status
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null | head -50
```

#### Resolution

| Cause | Fix |
|-------|-----|
| Container crashed | `docker restart db-alpha` |
| Disk full | Clean old data, increase volume size |
| Corrupted tablespace | Restore from backup: `bash scripts/restore.sh alpha <backup-dir>` |
| Too many connections | Increase `max_connections`; investigate connection leaks |
| InnoDB crash recovery | Usually auto-recovers; check logs |

```bash
# Restart database
docker restart db-alpha

# If data is corrupted, restore from backup
bash scripts/backup.sh alpha   # backup current state first
bash scripts/restore.sh alpha ./backups/<latest>

# Force recreate
docker compose up -d --force-recreate db-alpha
```

---

### High DB Connections

**Alert**: `MariaDBHighConnections`
**Severity**: 🟡 Warning
**Condition**: Active connections > 80% of max_connections for 5 minutes

#### Diagnosis Steps

```bash
# 1. Check current connections
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SHOW STATUS LIKE 'Threads_connected';"

# 2. Check max connections setting
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SHOW VARIABLES LIKE 'max_connections';"

# 3. List active connections with details
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SELECT user, host, db, command, time, state FROM information_schema.processlist ORDER BY time DESC;"

# 4. Check for sleeping connections
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SELECT COUNT(*) as sleeping FROM information_schema.processlist WHERE command='Sleep';"
```

#### Resolution

```bash
# Kill idle connections older than 300s
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist WHERE command='Sleep' AND time > 300;" | tail -n +2 | \
  docker exec -i db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD"

# Increase max_connections (temporary)
docker exec db-alpha mariadb -u root -p"$ALPHA_DB_ROOT_PASSWORD" \
  -e "SET GLOBAL max_connections = 200;"
```

---

### High Memory

**Alert**: `ContainerHighMemory`
**Severity**: 🟡 Warning
**Condition**: Container memory usage > 90% of limit for 5 minutes

#### Diagnosis Steps

```bash
# 1. Check memory usage
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"

# 2. Check processes inside container
docker exec wp-alpha ps aux --sort=-%mem | head -10

# 3. Check PHP memory
docker exec wp-alpha php -r "echo ini_get('memory_limit');"
```

#### Resolution

| Cause | Fix |
|-------|-----|
| PHP memory leak | Restart container: `docker restart wp-alpha` |
| Too many Apache workers | Tune `MaxRequestWorkers` in Apache config |
| Large file uploads | Limit `client_max_body_size` in Nginx |
| Insufficient limits | Increase memory limit in Docker Compose |

```bash
# Restart container (clears memory)
docker restart wp-alpha

# Increase memory limit (add to docker-compose.yml)
# services:
#   wp-alpha:
#     deploy:
#       resources:
#         limits:
#           memory: 512M
```

---

## Common Operations

### Scale: Add a New Tenant

See [README.md — Tenant Onboarding](README.md#tenant-onboarding).

```bash
bash scripts/onboard-tenant.sh gamma tenant-gamma.localhost
```

### Backup & Restore

```bash
# Backup all
make backup

# Restore specific tenant
make restore TENANT=alpha BACKUP_DIR=./backups/20240115_120000
```

### Update WordPress Version

```bash
# Pull new WordPress image
docker compose pull wp-alpha wp-beta

# Recreate containers (preserves volumes)
docker compose up -d --force-recreate wp-alpha wp-beta
```

### View Logs in Grafana

1. Open http://localhost:3000
2. Navigate to **Explore** → Select **Loki** data source
3. Query: `{container="wp-alpha"}` for Tenant Alpha logs
4. Query: `{service_type="database", tenant="alpha"}` for DB logs

### Check Prometheus Targets

1. Open http://localhost:9090/targets
2. Verify all targets show **UP** state
3. If a target is **DOWN**, check the corresponding container

---

## Troubleshooting Guide

| Symptom | Check | Fix |
|---------|-------|-----|
| Tenant page returns 502 | `docker logs wp-nginx` | Restart WP container |
| Tenant page returns 444 | Host header mismatch | Update hosts file |
| Grafana shows no data | Prometheus targets page | Check exporter containers |
| Loki shows no logs | Promtail container status | Verify Docker socket mount |
| "Connection refused" on port 80 | `docker ps` for nginx | Restart Nginx: `docker restart wp-nginx` |
| Database migration errors | `docker logs db-alpha` | Check volume permissions |

---

## Escalation Matrix

| Level | Scope | Action |
|-------|-------|--------|
| **L1** | Container restart, log review | `docker restart <container>` |
| **L2** | Configuration changes, backup/restore | Edit compose files, run restore script |
| **L3** | Data recovery, architecture changes | Restore from offsite backup, rebuild stack |
