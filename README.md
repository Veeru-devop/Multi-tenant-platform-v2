# WordPress Multitenancy Platform

A reproducible, local, production-like multi-tenant WordPress platform built with Docker Compose. Designed for serving multiple isolated WordPress tenants from shared infrastructure with full observability, CI/CD pipelines, and security controls.

![Platform](https://img.shields.io/badge/Platform-Docker%20Compose-2496ED?logo=docker)
![WordPress](https://img.shields.io/badge/WordPress-6.x-21759B?logo=wordpress)
![Monitoring](https://img.shields.io/badge/Monitoring-Prometheus%20%2B%20Grafana-E6522C?logo=prometheus)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions)

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start (Linux / Mac)](#quick-start)
- [Windows Setup (Native)](#windows-setup-native)
- [WSL2 + Docker Desktop Setup](#wsl2--docker-desktop-setup)
- [Tenant Onboarding](#tenant-onboarding)
- [Accessing Services](#accessing-services)
- [CI/CD Pipeline](#cicd-pipeline)
- [Versioning & Rollback](#versioning--rollback)
- [Observability](#observability)
- [Backup & Restore](#backup--restore)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)

---

## Architecture

```
                         ┌──────────────────────┐
                         │    Nginx Reverse      │
                         │    Proxy (:80)         │
                         └────────┬───────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │                             │
        ┌───────────▼──────────┐     ┌───────────▼──────────┐
        │  WordPress Alpha     │     │  WordPress Beta       │
        │  (wp-alpha)          │     │  (wp-beta)            │
        └───────────┬──────────┘     └───────────┬──────────┘
                    │                             │
        ┌───────────▼──────────┐     ┌───────────▼──────────┐
        │  MariaDB Alpha       │     │  MariaDB Beta         │
        │  (db-alpha)          │     │  (db-beta)            │
        │  [internal network]  │     │  [internal network]   │
        └──────────────────────┘     └──────────────────────┘

        ┌──────────────────────────────────────────────────────┐
        │                 Observability Stack                    │
        │  Prometheus │ Grafana │ Loki │ Promtail │ cAdvisor   │
        │  MySQL Exporters (per tenant) │ Nginx Exporter       │
        └──────────────────────────────────────────────────────┘
```

For a detailed architecture diagram see [ARCHITECTURE.md](ARCHITECTURE.md).

### Key Isolation

| Layer | Isolation Method |
|-------|--------------------|
| **Database** | Separate MariaDB container per tenant on internal-only Docker networks |
| **File Storage** | Dedicated Docker volumes per tenant (`wp_alpha_data`, `wp_alpha_uploads`) |
| **Network** | Backend networks marked `internal: true` — no external access to DB |
| **Configuration** | Per-tenant environment variables via `.env` file |

---

## Prerequisites

- **Docker Desktop** ≥ 4.x (includes Docker Compose V2)
  - [Install Docker Desktop](https://docs.docker.com/get-docker/)
- **Git** (for cloning the repository)
- **Make** (optional, for convenience commands)
  - Windows: available via Git Bash, WSL, or [GnuWin32](http://gnuwin32.sourceforge.net/packages/make.htm)

---

## Quick Start

> **Note:** This section covers **Linux / Mac**. For Windows, see [Windows Setup](#windows-setup-native) or [WSL2 Setup](#wsl2--docker-desktop-setup) below.

### 1. Clone the repository

```bash
git clone https://github.com/your-org/wp-multitenant-platform.git
cd wp-multitenant-platform
```

### 2. Run setup

```bash
# Generate .env with random passwords, validate Docker
bash scripts/setup.sh
```

### 3. Configure hosts file

Add to `/etc/hosts`:

```
127.0.0.1  tenant-alpha.localhost
127.0.0.1  tenant-beta.localhost
```

### 4. Start everything

```bash
# One command to start the entire platform + monitoring
make up
```

Or without Make:

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

### 5. Verify

| Service | URL |
|---------|-----|
| Tenant Alpha (WordPress) | http://tenant-alpha.localhost |
| Tenant Beta (WordPress) | http://tenant-beta.localhost |
| Grafana Dashboard | http://localhost:3000 |
| Prometheus | http://localhost:9090 |

---

## Windows Setup (Native)

For users running **Docker Desktop directly on Windows** (no WSL required).

### Prerequisites

Install all prerequisites in one command using **PowerShell (Run as Administrator)**:

```powershell
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements; `
winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements; `
winget install --id GnuWin32.Make -e --accept-package-agreements --accept-source-agreements
```

> ⚠️ **Reboot** after installing Docker Desktop, then open Docker Desktop and wait for the Engine to start.

### 1. Clone the repository

```powershell
git clone https://github.com/Veeru-devop/Multi-tenant-platform-v2
```

### 2. Run the Windows setup script (single command)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
```

This script automatically:
- ✅ Checks and installs missing prerequisites (Git, Docker Desktop, Make)
- ✅ Validates Docker Engine is running
- ✅ Generates `.env` with random passwords
- ✅ Creates required directories (`backups/`, `nginx/ssl/`)
- ✅ Adds tenant entries to `C:\Windows\System32\drivers\etc\hosts`
- ✅ Flushes DNS cache
- ✅ Starts the full platform with `docker compose up -d`

### 3. Verify

| Service | URL |
|---------|-----|
| Tenant Alpha (WordPress) | http://tenant-alpha.localhost |
| Tenant Beta (WordPress) | http://tenant-beta.localhost |
| Grafana Dashboard | http://localhost:3000 |
| Prometheus | http://localhost:9090 |

### Manual Setup (without the script)

If you prefer to run each step manually in PowerShell:

<details>
<summary>Click to expand manual steps</summary>

**Generate .env:**

```powershell
Copy-Item .env.example .env

function New-RandomPassword {
    -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
}

$content = Get-Content .env -Raw
$content = $content -replace 'alpha_root_change_me', (New-RandomPassword)
$content = $content -replace 'alpha_db_change_me',   (New-RandomPassword)
$content = $content -replace 'beta_root_change_me',  (New-RandomPassword)
$content = $content -replace 'beta_db_change_me',    (New-RandomPassword)
$content = $content -replace 'grafana_change_me',    (New-RandomPassword)
$content | Set-Content .env -NoNewline
```

**Create directories:**

```powershell
New-Item -ItemType Directory -Force -Path backups, nginx\ssl | Out-Null
```

**Configure hosts file (Run as Administrator):**

```powershell
Add-Content C:\Windows\System32\drivers\etc\hosts "`n127.0.0.1  tenant-alpha.localhost`n127.0.0.1  tenant-beta.localhost"
```

**Start the platform:**

```powershell
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

</details>

### Windows Command Reference

Since `make` may not be available on all Windows setups, here are the direct `docker compose` equivalents:

| Task | Command |
|------|---------|
| Start all services | `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d` |
| Stop all services | `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down` |
| View logs | `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs -f` |
| Check status | `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps` |
| Validate config | `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml config --quiet` |
| Clean up (⚠️) | `docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down -v --remove-orphans` |

### Windows Troubleshooting

| Issue | Fix |
|-------|-----|
| Port 80 already in use | IIS or W3SVC may be running. Stop it: `net stop W3SVC` — or set `NGINX_HTTP_PORT=8080` in `.env` |
| `make` not found | Install via `winget install GnuWin32.Make` or use `docker compose` commands directly (see table above) |
| Line ending issues (CRLF) | Run `git config core.autocrlf input` and re-clone. Docker containers need LF line endings. |
| Docker daemon not running | Open Docker Desktop, wait for the whale icon in system tray to stop animating |
| `scripts\setup.sh` fails | Use `scripts\setup-windows.ps1` instead — the `.sh` script uses Linux-only tools |

---

## WSL2 + Docker Desktop Setup

> 💡 **Recommended for Windows users.** WSL2 provides a native Linux environment where all project scripts (`setup.sh`, `Makefile`, etc.) work without modification.

### Prerequisites

#### Step 1 — Install WSL2 (from elevated PowerShell)

```powershell
wsl --install
```

> ⚠️ **Reboot** after this command. Ubuntu will launch automatically and prompt you to create a Linux username and password.

#### Step 2 — Install Docker Desktop for Windows

```powershell
winget install --id Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements
```

#### Step 3 — Enable Docker Desktop WSL Integration

1. Open **Docker Desktop** on Windows
2. Go to **Settings → Resources → WSL Integration**
3. Toggle **ON** for your Ubuntu distro
4. Click **Apply & Restart**

> This makes `docker` and `docker compose` available inside your WSL shell without a separate Docker installation.

### 1. Open WSL Terminal

```powershell
# From PowerShell or Windows Terminal
wsl
```

Or open **"Ubuntu"** from the Start Menu.

### 2. Install system dependencies (inside WSL)

```bash
sudo apt update && sudo apt install -y make git curl
```

### 3. Clone the repository

```bash
# Clone inside WSL filesystem for best performance (NOT on /mnt/c/)
cd ~
git clone https://github.com/your-org/wp-multitenant-platform.git
cd wp-multitenant-platform
```

> ⚠️ **Performance tip:** Always clone inside the WSL filesystem (`~/...`), not on `/mnt/c/...`. The Windows mount is significantly slower for Docker bind mounts.

### 4. Run the WSL setup script (single command)

```bash
bash scripts/setup-wsl.sh
```

This script automatically:
- ✅ Verifies you are running inside WSL2 (not WSL1)
- ✅ Installs missing system packages (`make`, `git`, `curl`)
- ✅ Verifies Docker Desktop WSL integration is working
- ✅ Runs the standard `setup.sh` (generates `.env`, creates directories)
- ✅ Configures hosts file on **both** Windows (`/mnt/c/Windows/...`) and WSL (`/etc/hosts`)
- ✅ Starts the full platform via `make up`

### Alternative: Run each step separately

```bash
# Step A — Run standard setup
bash scripts/setup.sh

# Step B — Configure Windows hosts file from WSL
echo -e "127.0.0.1  tenant-alpha.localhost\n127.0.0.1  tenant-beta.localhost" | \
  sudo tee -a /mnt/c/Windows/System32/drivers/etc/hosts > /dev/null

# Step C — Start the platform
make up
```

### 5. Verify

Open your **Windows browser** (not a browser inside WSL) and visit:

| Service | URL |
|---------|-----|
| Tenant Alpha (WordPress) | http://tenant-alpha.localhost |
| Tenant Beta (WordPress) | http://tenant-beta.localhost |
| Grafana Dashboard | http://localhost:3000 |
| Prometheus | http://localhost:9090 |

### WSL Command Reference

All standard `make` commands work natively in WSL:

| Command | Description |
|---------|-------------|
| `make up` | Start all services (platform + monitoring) |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make logs` | Follow logs for all services |
| `make status` | Show container health status |
| `make backup` | Backup all tenants |
| `make clean` | Stop and remove all volumes (⚠️ destructive) |
| `make validate` | Validate Docker Compose config |
| `make shell-alpha` | Open shell in Tenant Alpha |
| `make db-alpha` | Open MariaDB CLI for Tenant Alpha |

### WSL Troubleshooting

| Issue | Fix |
|-------|-----|
| `docker: command not found` | Enable Docker Desktop WSL Integration: Settings → Resources → WSL Integration → Toggle ON for your distro |
| Slow file I/O / builds | Clone repo inside WSL filesystem (`~/projects/...`), not on `/mnt/c/...` |
| Cannot access sites in browser | WSL2 auto-forwards ports to Windows `localhost`. Restart Docker Desktop if not working |
| `make: command not found` | Run `sudo apt install make` inside WSL |
| WSL1 instead of WSL2 | Convert: `wsl --set-version Ubuntu 2` (from PowerShell) |
| Hosts file permission denied | Use `sudo` when editing from WSL: `sudo tee -a /mnt/c/Windows/...` |

---

## Tenant Onboarding

### Adding a new tenant

```bash
# Automated onboarding
make onboard TENANT=gamma DOMAIN=tenant-gamma.localhost

# Or directly:
bash scripts/onboard-tenant.sh gamma tenant-gamma.localhost
```

This generates:
1. **Docker Compose overlay** — `docker-compose.tenant-gamma.yml`
2. **Environment variables** — appended to `.env`
3. **Nginx config snippet** — `nginx/tenant-gamma.conf.snippet`

### Manual steps after onboarding:

1. **Update `nginx/nginx.conf`** — Add the upstream and server block from the generated snippet
2. **Update hosts file** — Add `127.0.0.1 tenant-gamma.localhost`
3. **Start the tenant:**
   ```bash
   docker compose -f docker-compose.yml \
     -f docker-compose.tenant-gamma.yml \
     -f docker-compose.monitoring.yml up -d
   ```
4. **Complete WordPress installation** at `http://tenant-gamma.localhost`

### Removing a tenant

```bash
# Stop tenant containers
docker compose -f docker-compose.yml -f docker-compose.tenant-gamma.yml down

# Remove volumes (⚠️ destructive)
docker volume rm wp_gamma_data wp_gamma_uploads db_gamma_data

# Clean up files
rm docker-compose.tenant-gamma.yml
rm nginx/tenant-gamma.conf.snippet
# Remove entries from .env and nginx/nginx.conf
```

---

## CI/CD Pipeline

### PR Checks (`.github/workflows/ci.yml`)

Runs on every pull request targeting `main` or `develop`:

| Job | Description |
|-----|-------------|
| **PHP Lint** | Syntax check all `.php` files using `php-parallel-lint` |
| **PHPCS** | WordPress Coding Standards validation via `wp-coding-standards/wpcs` |
| **Security Scan** | PHPStan static analysis + `composer audit` for known vulnerabilities |
| **Docker Validate** | Validates Docker Compose configuration syntax |

### Build & Deploy (`.github/workflows/cd.yml`)

Runs on push to `main` or version tags (`v*`):

| Job | Description |
|-----|-------------|
| **Build Artifacts** | Creates versioned zip archives: `starter-theme-v1.0.0.zip`, `starter-plugin-v1.0.0.zip` |
| **Simulate Deploy** | Spins up Docker Compose, deploys artifacts, runs health checks |
| **Create Release** | (Tag only) Creates GitHub release with attached zip artifacts |

### Local Testing with `act`

You can test these GitHub Actions locally on Windows using `act`:

1. **Install `act`:**
   ```powershell
   winget install nektos.act
   ```
2. **Initialize Git (if not already a repo):**
   The deployment scripts rely on `git rev-parse`, so the codebase must be recognized as a valid git repository.
   ```powershell
   git init
   git add .
   git commit -m "initial commit"
   ```
3. **Run CI Pipeline (Pull Request):**
   ```powershell
   act pull_request
   ```
4. **Run CD Pipeline (Push):**
   Since the local runner lacks GitHub's native artifact storage, supply a local path to `--artifact-server-path` so the deploy job can download what the build job compiled.
   ```powershell
   act push --artifact-server-path artifacts
   ```
   > ⚠️ **Note:** `act` simulates actions locally. Complex jobs (like `docker compose` with multi-stack paths) might cause localized mounting errors that will not occur on actual native GitHub hosted runners. Always test final configurations on a live fork!

---

## Versioning & Rollback

### Versioning Strategy

- **Tags** follow [Semantic Versioning](https://semver.org/): `v1.0.0`, `v1.1.0`, `v2.0.0`
- **Non-tag builds** use: `dev-<short-sha>` (e.g., `dev-abc1234`)
- Version is injected into `style.css` and plugin headers during build

### Creating a release

```bash
git tag v1.0.0
git push origin v1.0.0
# GitHub Actions will build artifacts and create a release
```

### Rollback procedure

1. Go to **GitHub Releases** and download the previous version's zip artifacts
2. Deploy manually:
   ```bash
   # Copy artifact into container
   docker cp starter-theme-v0.9.0.zip wp-alpha:/tmp/theme.zip
   docker exec wp-alpha bash -c \
     "cd /var/www/html/wp-content/themes && unzip -o /tmp/theme.zip && rm /tmp/theme.zip"
   ```
3. Or re-tag and push to trigger automated deployment:
   ```bash
   git tag v1.0.1  # point to the known-good commit
   git push origin v1.0.1
   ```

---

## Observability

The monitoring stack is defined in `docker-compose.monitoring.yml` and includes:

| Component | Purpose | Port |
|-----------|---------|------|
| **Prometheus** | Metrics collection & alerting | `:9090` |
| **Grafana** | Dashboards & visualization | `:3000` |
| **Loki** | Log aggregation | `:3100` |
| **Promtail** | Log shipping (Docker → Loki) | — |
| **cAdvisor** | Container resource metrics | `:8081` |
| **MySQL Exporter (×2)** | Per-tenant DB metrics | — |
| **Nginx Exporter** | Reverse proxy metrics | — |

### Grafana Dashboard

The **"WordPress Multitenancy Platform"** dashboard is auto-provisioned and includes:
- Platform service health indicators (UP/DOWN)
- Nginx request rate
- Container CPU & memory usage per tenant
- Database connections, queries/sec, slow queries
- Centralized log viewer across all tenants

### Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| `WordPressContainerDown` | WP container not seen for 60s | 🔴 Critical |
| `NginxHighLatency` | Avg response time > 2s for 5m | 🟡 Warning |
| `MariaDBExporterDown` | MySQL exporter unreachable for 1m | 🔴 Critical |
| `MariaDBHighConnections` | DB connections > 80% of max for 5m | 🟡 Warning |
| `ContainerHighMemory` | Container memory > 90% limit for 5m | 🟡 Warning |

See [RUNBOOK.md](RUNBOOK.md) for alert response procedures.

---

## Backup & Restore

### Backup all tenants

```bash
make backup
# or: bash scripts/backup.sh
```

### Backup specific tenant

```bash
bash scripts/backup.sh alpha
```

### Restore a tenant

```bash
make restore TENANT=alpha BACKUP_DIR=./backups/20240115_120000
# or: bash scripts/restore.sh alpha ./backups/20240115_120000
```

Backups include:
- Full database dump (MariaDB)
- WordPress uploads directory
- wp-config.php

---

## Project Structure

```
├── docker-compose.yml              # Core platform (Nginx + WP + DB)
├── docker-compose.monitoring.yml   # Observability stack (overlay)
├── .env.example                    # Environment template
├── Makefile                        # One-command operations
├── README.md                       # This file
├── ARCHITECTURE.md                 # Detailed architecture docs
├── SECURITY.md                     # Security analysis
├── RUNBOOK.md                      # Operational runbook
│
├── nginx/
│   └── nginx.conf                  # Reverse proxy configuration
│
├── scripts/
│   ├── setup.sh                    # Initial setup wizard (Linux/Mac)
│   ├── setup-windows.ps1           # Initial setup wizard (Windows native)
│   ├── setup-wsl.sh                # Initial setup wizard (WSL2 + Docker Desktop)
│   ├── onboard-tenant.sh           # New tenant onboarding
│   ├── backup.sh                   # Backup automation
│   └── restore.sh                  # Restore from backup
│
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml          # Scrape targets
│   │   └── alert-rules.yml         # Alert definitions
│   ├── grafana/provisioning/       # Auto-provisioned dashboards & datasources
│   ├── loki/loki-config.yml        # Log storage config
│   └── promtail/promtail-config.yml # Log shipping config
│
├── wp-content/
│   ├── themes/starter-theme/       # Example theme (CI/CD target)
│   └── plugins/starter-plugin/     # Example plugin (CI/CD target)
│
└── .github/workflows/
    ├── ci.yml                      # PR checks pipeline
    └── cd.yml                      # Build & deploy pipeline
```

---

## Troubleshooting

### Containers won't start

```bash
# Check status
make status

# View logs
make logs

# Validate configuration
make validate
```

### "Host not found" when visiting tenant URL

Ensure your hosts file has the correct entries:
```
127.0.0.1  tenant-alpha.localhost
127.0.0.1  tenant-beta.localhost
```

### Database connection errors

```bash
# Check if database is healthy
docker inspect --format='{{.State.Health.Status}}' db-alpha

# View database logs
docker logs db-alpha
```

### Port conflicts

If port 80 is in use, edit `.env`:
```
NGINX_HTTP_PORT=8080
```
Then visit `http://tenant-alpha.localhost:8080`

### Reset everything

```bash
# ⚠️ This destroys all data
make clean
make setup
make up
```

---

## Available Make Commands

| Command | Description |
|---------|-------------|
| `make up` | Start all services (platform + monitoring) |
| `make up-wp` | Start WordPress services only |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make logs` | Follow logs for all services |
| `make status` | Show container health status |
| `make backup` | Backup all tenants |
| `make restore` | Restore a tenant from backup |
| `make onboard` | Onboard a new tenant |
| `make clean` | Stop and remove all volumes (⚠️ destructive) |
| `make validate` | Validate Docker Compose config |
| `make shell-alpha` | Open shell in Tenant Alpha |
| `make db-alpha` | Open MariaDB CLI for Tenant Alpha |

---

## License

This project is for demonstration and interview purposes.
