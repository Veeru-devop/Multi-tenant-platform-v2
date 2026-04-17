#!/usr/bin/env bash
# ==============================================================
# WordPress Multitenancy Platform — Initial Setup
# ==============================================================
# Generates .env from template, validates Docker, prints
# hosts file instructions.
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  WordPress Multitenancy Platform — Setup                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- Step 1: Check Docker ----
echo -e "${YELLOW}[1/4]${NC} Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed.${NC}"
    echo "  Please install Docker Desktop: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker daemon is not running.${NC}"
    echo "  Please start Docker Desktop and try again."
    exit 1
fi

DOCKER_VERSION=$(docker --version)
echo -e "${GREEN}✓ Docker found: ${DOCKER_VERSION}${NC}"

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo -e "${RED}✗ Docker Compose V2 not found.${NC}"
    echo "  Please update Docker Desktop or install docker-compose-plugin."
    exit 1
fi

COMPOSE_VERSION=$(docker compose version --short)
echo -e "${GREEN}✓ Docker Compose: v${COMPOSE_VERSION}${NC}"

# ---- Step 2: Generate .env ----
echo ""
echo -e "${YELLOW}[2/4]${NC} Generating .env file..."

ENV_FILE="$PROJECT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠  .env file already exists. Skipping generation.${NC}"
    echo "   Delete .env and re-run setup to regenerate."
else
    # Generate random passwords
    generate_password() {
        # Generate a 24-char alphanumeric password
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1
    }

    cp "$PROJECT_DIR/.env.example" "$ENV_FILE"

    # Replace placeholder passwords with generated ones
    sed -i "s/alpha_root_change_me/$(generate_password)/g" "$ENV_FILE"
    sed -i "s/alpha_db_change_me/$(generate_password)/g" "$ENV_FILE"
    sed -i "s/beta_root_change_me/$(generate_password)/g" "$ENV_FILE"
    sed -i "s/beta_db_change_me/$(generate_password)/g" "$ENV_FILE"
    sed -i "s/grafana_change_me/$(generate_password)/g" "$ENV_FILE"

    echo -e "${GREEN}✓ .env generated with random passwords.${NC}"
    echo -e "  ${YELLOW}IMPORTANT: Never commit .env to git!${NC}"
fi

# ---- Step 3: Create required directories ----
echo ""
echo -e "${YELLOW}[3/4]${NC} Creating directories..."

mkdir -p "$PROJECT_DIR/backups"
mkdir -p "$PROJECT_DIR/nginx/ssl"

echo -e "${GREEN}✓ Directories created.${NC}"

# ---- Step 4: Hosts file instructions ----
echo ""
echo -e "${YELLOW}[4/4]${NC} Hosts file configuration..."
echo ""
echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│  Add these lines to your hosts file:                   │${NC}"
echo -e "${BLUE}│                                                        │${NC}"
echo -e "${BLUE}│  Windows: C:\\Windows\\System32\\drivers\\etc\\hosts         │${NC}"
echo -e "${BLUE}│  Linux/Mac: /etc/hosts                                 │${NC}"
echo -e "${BLUE}│                                                        │${NC}"
echo -e "${BLUE}│  127.0.0.1  tenant-alpha.localhost                     │${NC}"
echo -e "${BLUE}│  127.0.0.1  tenant-beta.localhost                      │${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
echo ""

# ---- Done ----
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅  Setup complete!                                    ║"
echo "║                                                        ║"
echo "║  Next steps:                                           ║"
echo "║  1. Update your hosts file (see above)                 ║"
echo "║  2. Run: make up                                       ║"
echo "║  3. Visit: http://tenant-alpha.localhost                ║"
echo "║  4. Visit: http://tenant-beta.localhost                 ║"
echo "║  5. Grafana: http://localhost:3000                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
