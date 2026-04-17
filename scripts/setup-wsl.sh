#!/usr/bin/env bash
# ==============================================================
# WordPress Multitenancy Platform — WSL + Docker Desktop Setup
# ==============================================================
# Run this script INSIDE your WSL2 terminal (Ubuntu):
#
#   bash scripts/setup-wsl.sh
#
# This script will:
#   1. Verify you are running inside WSL2
#   2. Install system dependencies (make, git, curl)
#   3. Verify Docker Desktop WSL integration is working
#   4. Run the standard setup.sh (generate .env, etc.)
#   5. Configure the Windows hosts file (via /mnt/c)
#   6. Start the entire platform
#
# Prerequisites:
#   - WSL2 installed (run 'wsl --install' from PowerShell)
#   - Docker Desktop for Windows installed and running
#   - Docker Desktop → Settings → Resources → WSL Integration
#     → Toggle ON for your Ubuntu distro
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  WordPress Multitenancy Platform — WSL Setup            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ==============================================================
# Step 1 — Verify WSL2 Environment
# ==============================================================
echo -e "${YELLOW}[1/6]${NC} Verifying WSL2 environment..."

if [ -z "${WSL_DISTRO_NAME:-}" ] && ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${RED}✗ This script must be run inside WSL2.${NC}"
    echo "  To install WSL2, run from PowerShell (as Admin):"
    echo "    wsl --install"
    echo ""
    echo "  After reboot, open Ubuntu from Start Menu and re-run this script."
    exit 1
fi

WSL_VER="2"
if [ -f /proc/version ]; then
    if grep -qi "microsoft" /proc/version; then
        echo -e "${GREEN}✓ Running inside WSL ($(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"'))${NC}"
    fi
fi

# Check WSL version (should be 2 for Docker Desktop integration)
if command -v wsl.exe &> /dev/null; then
    WSL_VER_CHECK=$(wsl.exe -l -v 2>/dev/null | grep -i "${WSL_DISTRO_NAME:-Ubuntu}" | awk '{print $NF}' || echo "2")
    if [ "$WSL_VER_CHECK" = "1" ]; then
        echo -e "${YELLOW}⚠ You appear to be running WSL1. Docker Desktop requires WSL2.${NC}"
        echo "  Convert your distro: wsl --set-version ${WSL_DISTRO_NAME:-Ubuntu} 2"
        echo "  Or set default:      wsl --set-default-version 2"
    fi
fi

# ==============================================================
# Step 2 — Install System Dependencies
# ==============================================================
echo ""
echo -e "${YELLOW}[2/6]${NC} Installing system dependencies..."

PACKAGES_NEEDED=""
for pkg in make git curl; do
    if ! command -v $pkg &> /dev/null; then
        PACKAGES_NEEDED="$PACKAGES_NEEDED $pkg"
    else
        echo -e "${GREEN}✓ $pkg is installed${NC}"
    fi
done

if [ -n "$PACKAGES_NEEDED" ]; then
    echo -e "${CYAN}  Installing:${NC}$PACKAGES_NEEDED"
    sudo apt-get update -qq
    sudo apt-get install -y -qq $PACKAGES_NEEDED
    echo -e "${GREEN}✓ Dependencies installed${NC}"
fi

# ==============================================================
# Step 3 — Verify Docker Desktop Integration
# ==============================================================
echo ""
echo -e "${YELLOW}[3/6]${NC} Verifying Docker Desktop integration..."

# Check docker command exists
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ 'docker' command not found in WSL.${NC}"
    echo ""
    echo "  This means Docker Desktop WSL integration is not enabled."
    echo "  Fix it:"
    echo "    1. Open Docker Desktop on Windows"
    echo "    2. Go to Settings → Resources → WSL Integration"
    echo "    3. Toggle ON for '${WSL_DISTRO_NAME:-Ubuntu}'"
    echo "    4. Click 'Apply & Restart'"
    echo "    5. Close and re-open your WSL terminal"
    echo "    6. Re-run this script"
    exit 1
fi

# Check docker daemon is accessible
if ! docker info &> /dev/null 2>&1; then
    echo -e "${RED}✗ Docker daemon is not accessible.${NC}"
    echo ""
    echo "  Possible causes:"
    echo "    - Docker Desktop is not running (start it from Windows)"
    echo "    - WSL integration is not enabled for this distro"
    echo ""
    echo "  Fix:"
    echo "    1. Start Docker Desktop on Windows"
    echo "    2. Wait for it to fully load (whale icon stops animating)"
    echo "    3. Settings → Resources → WSL Integration → Enable for '${WSL_DISTRO_NAME:-Ubuntu}'"
    echo "    4. Re-run this script"
    exit 1
fi

DOCKER_VER=$(docker --version)
echo -e "${GREEN}✓ Docker accessible: ${DOCKER_VER}${NC}"

# Verify Docker Compose V2
if ! docker compose version &> /dev/null 2>&1; then
    echo -e "${RED}✗ Docker Compose V2 not available.${NC}"
    echo "  Please update Docker Desktop to latest version."
    exit 1
fi

COMPOSE_VER=$(docker compose version --short)
echo -e "${GREEN}✓ Docker Compose V2: v${COMPOSE_VER}${NC}"

# ==============================================================
# Step 4 — Run Standard Setup (generate .env, dirs)
# ==============================================================
echo ""
echo -e "${YELLOW}[4/6]${NC} Running platform setup..."

# Check if we are on a Windows mount (will be slow)
case "$PROJECT_DIR" in
    /mnt/c/*|/mnt/d/*|/mnt/e/*)
        echo -e "${YELLOW}⚠  WARNING: Project is on a Windows mount ($PROJECT_DIR)${NC}"
        echo -e "${YELLOW}   Docker bind-mount performance will be SLOW.${NC}"
        echo -e "${YELLOW}   For best performance, clone inside WSL filesystem:${NC}"
        echo -e "${YELLOW}     cd ~ && git clone <repo-url> && cd wp-multitenant-platform${NC}"
        echo ""
        ;;
esac

# Run the existing setup.sh
bash "$SCRIPT_DIR/setup.sh"

# ==============================================================
# Step 5 — Configure Windows Hosts File
# ==============================================================
echo ""
echo -e "${YELLOW}[5/6]${NC} Configuring Windows hosts file..."

WIN_HOSTS="/mnt/c/Windows/System32/drivers/etc/hosts"
HOSTS_ENTRIES=(
    "127.0.0.1  tenant-alpha.localhost"
    "127.0.0.1  tenant-beta.localhost"
)

if [ -f "$WIN_HOSTS" ]; then
    HOSTS_CHANGED=false

    for entry in "${HOSTS_ENTRIES[@]}"; do
        if grep -qF "$entry" "$WIN_HOSTS" 2>/dev/null; then
            echo -e "${GREEN}✓ Already in hosts: $entry${NC}"
        else
            echo "$entry" | sudo tee -a "$WIN_HOSTS" > /dev/null
            echo -e "${GREEN}✓ Added to hosts: $entry${NC}"
            HOSTS_CHANGED=true
        fi
    done

    if $HOSTS_CHANGED; then
        # Try to flush Windows DNS from WSL
        if command -v ipconfig.exe &> /dev/null; then
            ipconfig.exe /flushdns > /dev/null 2>&1 || true
            echo -e "${GREEN}✓ Windows DNS cache flushed${NC}"
        fi
    fi

    # Also update WSL's own /etc/hosts for curl/wget tests inside WSL
    for entry in "${HOSTS_ENTRIES[@]}"; do
        if ! grep -qF "$entry" /etc/hosts 2>/dev/null; then
            echo "$entry" | sudo tee -a /etc/hosts > /dev/null
        fi
    done
    echo -e "${GREEN}✓ WSL /etc/hosts also updated${NC}"
else
    echo -e "${YELLOW}⚠ Could not find Windows hosts file at $WIN_HOSTS${NC}"
    echo "  Please add these entries manually to C:\\Windows\\System32\\drivers\\etc\\hosts:"
    for entry in "${HOSTS_ENTRIES[@]}"; do
        echo "    $entry"
    done
fi

# ==============================================================
# Step 6 — Start the Platform
# ==============================================================
echo ""
echo -e "${YELLOW}[6/6]${NC} Starting the platform..."

cd "$PROJECT_DIR"
echo -e "${CYAN}  Running: make up${NC}"
make up

# ==============================================================
# Done!
# ==============================================================
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅  WSL Setup complete! Platform is starting...        ║"
echo "║                                                        ║"
echo "║  Open your WINDOWS browser and visit:                  ║"
echo "║                                                        ║"
echo "║    Tenant Alpha:   http://tenant-alpha.localhost       ║"
echo "║    Tenant Beta:    http://tenant-beta.localhost        ║"
echo "║    Grafana:        http://localhost:3000               ║"
echo "║    Prometheus:     http://localhost:9090               ║"
echo "║                                                        ║"
echo "║  Useful commands (run from this WSL terminal):         ║"
echo "║    make status    — Check container health             ║"
echo "║    make logs      — Follow all logs                    ║"
echo "║    make down      — Stop everything                    ║"
echo "║    make backup    — Backup all tenants                 ║"
echo "║    make clean     — Remove everything (⚠️  destructive) ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
