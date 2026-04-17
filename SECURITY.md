# Security Analysis — WordPress Multitenancy Platform

## Table of Contents

- [1. Tenant Isolation Risks](#1-tenant-isolation-risks)
- [2. Secrets Management](#2-secrets-management)
- [3. WordPress-Specific Risks](#3-wordpress-specific-risks)
- [4. CI/CD Supply-Chain Risks](#4-cicd-supply-chain-risks)
- [5. Backup & Recovery](#5-backup--recovery)
- [6. Network Security](#6-network-security)
- [7. Monitoring & Detection](#7-monitoring--detection)

---

## 1. Tenant Isolation Risks

### Risks

| Risk | Severity | Description |
|------|----------|-------------|
| **Cross-tenant DB access** | 🔴 Critical | A compromised WordPress instance could attempt to access another tenant's database |
| **Shared filesystem escape** | 🟡 Medium | WordPress containers share the Docker daemon; a container escape could access host filesystem |
| **Noisy neighbor** | 🟡 Medium | One tenant consuming excessive CPU/memory affects others |
| **Shared Nginx process** | 🟢 Low | A vulnerability in Nginx could expose routing info for all tenants |

### Mitigations

- ✅ **Network isolation**: Backend networks are `internal: true` — each tenant's DB is on a dedicated network unreachable from other tenants
- ✅ **Separate DB instances**: Each tenant runs its own MariaDB container with unique credentials
- ✅ **Separate volumes**: WordPress data and uploads use dedicated Docker volumes per tenant
- ✅ **Resource limits**: Can be added via `deploy.resources.limits` in Docker Compose (recommended for production)
- ✅ **No cross-network routes**: `wp-alpha` cannot resolve or connect to `db-beta`
- 🔧 **Recommendation**: Add `read_only: true` to WordPress containers and use `tmpfs` for writable directories
- 🔧 **Recommendation**: Enable Docker user namespaces to prevent container root from mapping to host root

---

## 2. Secrets Management

### Current Approach

| Method | What | Where |
|--------|------|-------|
| `.env` file | Database passwords, Grafana credentials | Host filesystem, never committed to git |
| `.env.example` | Template with placeholder values | Committed to git (safe — no real secrets) |
| `setup.sh` | Auto-generates random 24-char passwords | Runs once during initial setup |

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **`.env` committed to git** | 🔴 Critical | `.gitignore` excludes `.env`; pre-commit hook recommended |
| **Secrets in Docker inspect** | 🟡 Medium | Environment variables visible via `docker inspect`; use Docker secrets for production |
| **Weak passwords** | 🟡 Medium | `setup.sh` generates 24-char alphanumeric passwords automatically |
| **No secret rotation** | 🟡 Medium | Implement periodic rotation; database passwords require coordinated update |

### Production Recommendations

```
Local (.env files) → AWS Secrets Manager / SSM Parameter Store
                   → HashiCorp Vault
                   → Docker Swarm secrets
```

- Use **Docker secrets** (Swarm mode) or external secret managers in production
- Implement **secret rotation** with zero-downtime credential updates
- Add **pre-commit hooks** to scan for accidentally committed secrets:
  ```bash
  # .pre-commit-config.yaml
  - repo: https://github.com/gitleaks/gitleaks
    hooks:
      - id: gitleaks
  ```

---

## 3. WordPress-Specific Risks

### Risks & Mitigations

| Risk | Severity | Status | Mitigation |
|------|----------|--------|------------|
| **XML-RPC attacks** (brute force, DDoS amplification) | 🔴 Critical | ✅ Mitigated | Blocked at Nginx level (`return 403`) |
| **wp-login brute force** | 🔴 Critical | ✅ Mitigated | Nginx rate limiting (5 req/s with burst=3) |
| **File editor in admin** | 🟡 Medium | ✅ Mitigated | `DISALLOW_FILE_EDIT` set to `true` |
| **Auto-updates breaking site** | 🟡 Medium | ✅ Mitigated | `WP_AUTO_UPDATE_CORE` set to `false`; updates via CI/CD only |
| **WordPress version disclosure** | 🟢 Low | ✅ Mitigated | Generator meta tag removed via `starter-theme` |
| **Sensitive file exposure** | 🟡 Medium | ✅ Mitigated | Nginx blocks access to `wp-config.php`, `readme.html`, `license.txt` |
| **Plugin/theme vulnerabilities** | 🔴 Critical | 🔧 Partial | PHPCS + PHPStan in CI; recommend WPScan for runtime scanning |
| **REST API exposure** | 🟡 Medium | 🔧 Recommend | Restrict REST API to authenticated users for non-public endpoints |
| **wp-cron abuse** | 🟢 Low | 🔧 Recommend | Disable `wp-cron.php`; use system cron via `docker exec` |
| **Upload directory code execution** | 🟡 Medium | 🔧 Recommend | Add Nginx rule to deny `.php` execution in `/wp-content/uploads/` |

### Recommended Nginx additions for production:

```nginx
# Deny PHP execution in uploads
location ~* /wp-content/uploads/.*\.php$ {
    deny all;
    return 403;
}

# Restrict REST API
location /wp-json/ {
    # Allow only authenticated requests or specific endpoints
    limit_req zone=general burst=10 nodelay;
    proxy_pass http://upstream;
}
```

---

## 4. CI/CD Supply-Chain Risks

### Pipeline Security

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Compromised GitHub Actions** | 🔴 Critical | Pin actions to specific SHA: `actions/checkout@abc123` instead of `@v4` |
| **Dependency confusion** | 🟡 Medium | Use `composer audit` in CI to check for known vulnerabilities |
| **Malicious PR code execution** | 🟡 Medium | CI runs in isolated GitHub-hosted runners; no access to production |
| **Secrets in CI logs** | 🟡 Medium | Use GitHub Secrets for sensitive values; never `echo` secrets |
| **Unsigned artifacts** | 🟡 Medium | Recommend signing zip artifacts with GPG for integrity verification |
| **Stale dependencies** | 🟡 Medium | Run `composer audit` and consider Dependabot for automated updates |

### Recommended Improvements

1. **Pin action versions to SHAs** (not tags):
   ```yaml
   # Instead of:
   uses: actions/checkout@v4
   # Use:
   uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
   ```

2. **Add artifact signing**:
   ```bash
   gpg --armor --detach-sign starter-theme-v1.0.0.zip
   ```

3. **Enable branch protection**:
   - Require PR reviews before merge
   - Require status checks to pass
   - No force pushes to `main`

4. **CODEOWNERS** for critical files:
   ```
   # .github/CODEOWNERS
   docker-compose*.yml  @platform-team
   nginx/               @platform-team
   scripts/             @platform-team
   .github/workflows/   @platform-team
   ```

---

## 5. Backup & Recovery

### Current Strategy

| Aspect | Detail |
|--------|--------|
| **What's backed up** | Database (full `mysqldump`), uploads directory, `wp-config.php` |
| **Backup script** | `scripts/backup.sh` — automated, timestamped |
| **Restore script** | `scripts/restore.sh` — per-tenant, with confirmation prompt |
| **Storage** | Local `backups/` directory (gitignored) |
| **Frequency** | Manual (recommended: cron job for automated daily backups) |

### Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **No offsite backup** | 🔴 Critical | Production: replicate to S3 with versioning and cross-region replication |
| **Backup not encrypted** | 🟡 Medium | Encrypt backups at rest: `gpg --symmetric database.sql` |
| **No backup testing** | 🟡 Medium | Schedule monthly restore drills; automate restore testing in CI |
| **Point-in-time recovery** | 🟡 Medium | Enable MariaDB binary logging for PITR capability |

### Production Recommendations

```
# Automated daily backup with S3 upload
0 2 * * * /opt/platform/scripts/backup.sh && \
  aws s3 sync /opt/platform/backups/ s3://backups-bucket/ --sse

# RDS: Enable automated backups with 7-day retention
# EFS: Enable AWS Backup with cross-region copy
```

### Recovery Time Objectives

| Scenario | RTO | RPO |
|----------|-----|-----|
| Single tenant DB corruption | 15 min | Last backup (daily) |
| Full platform failure | 30 min | Last backup |
| Container crash | Automatic | 0 (Docker restart policy) |

---

## 6. Network Security

### Current Controls

- ✅ Backend networks marked `internal: true` — no external routing
- ✅ Only Nginx exposes ports 80 and 8080 to the host
- ✅ Database ports not exposed to host
- ✅ Security headers set at Nginx level

### Additional Recommendations

| Control | Priority | Description |
|---------|----------|-------------|
| **TLS/HTTPS** | 🔴 High | Add self-signed or Let's Encrypt certificates |
| **Docker socket protection** | 🟡 Medium | Promtail mounts Docker socket read-only; consider socket proxy |
| **Container hardening** | 🟡 Medium | Set `no-new-privileges`, drop Linux capabilities, use `read_only` |
| **Host firewall** | 🟢 Low | For local development, host firewall is optional |

### Container Hardening Example

```yaml
services:
  wp-alpha:
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
    read_only: true
    tmpfs:
      - /tmp
      - /var/run/apache2
```

---

## 7. Monitoring & Detection

### Security-Relevant Monitoring

| What | How | Alert |
|------|-----|-------|
| **Container crashes** | cAdvisor + Prometheus | `WordPressContainerDown` |
| **Brute force attempts** | Nginx rate limiting logs in Loki | Query for 429 status codes |
| **DB connection spikes** | MySQL exporter | `MariaDBHighConnections` |
| **Unexpected processes** | cAdvisor | Monitor process count per container |
| **Log volume anomalies** | Loki | Sudden spike in error logs |

### Grafana Query for Brute Force Detection

```logql
{container="wp-nginx"} |= "wp-login.php" | pattern `<_> <_> <_> [<_>] "<method> <path> <_>" <status> <_>` | status = "429"
```

---

## Summary: Security Posture

| Area | Score | Notes |
|------|-------|-------|
| Tenant Isolation | ⭐⭐⭐⭐ | Strong network + DB isolation; add resource limits |
| Secrets Management | ⭐⭐⭐ | Good for local dev; needs vault/rotation for prod |
| WordPress Hardening | ⭐⭐⭐⭐ | XML-RPC blocked, file edit disabled, version hidden |
| CI/CD Security | ⭐⭐⭐ | Linting + audit present; pin actions to SHA |
| Backup & Recovery | ⭐⭐⭐ | Scripts ready; needs offsite storage + encryption |
| Network Security | ⭐⭐⭐⭐ | Internal networks, minimal port exposure |
| Monitoring | ⭐⭐⭐⭐ | Full stack with alerts; add brute force detection |
