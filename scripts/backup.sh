#!/usr/bin/env bash
# ==============================================================
# WordPress Multitenancy Platform — Backup Script
# ==============================================================
# Backs up all tenant databases and WordPress uploads.
# Usage: ./scripts/backup.sh [tenant-name]
#   No argument = backup all tenants
#   With argument = backup specific tenant
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_DIR/backups/$TIMESTAMP"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  WordPress Multitenancy Platform — Backup               ║"
echo "║  Timestamp: $TIMESTAMP                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

mkdir -p "$BACKUP_DIR"

# ---- Backup function ----
backup_tenant() {
    local tenant="$1"
    local db_container="db-${tenant}"
    local wp_container="wp-${tenant}"

    echo -e "${YELLOW}Backing up tenant: ${tenant}${NC}"

    # Check container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${db_container}$"; then
        echo -e "${RED}✗ Container ${db_container} is not running. Skipping.${NC}"
        return 1
    fi

    local tenant_dir="$BACKUP_DIR/$tenant"
    mkdir -p "$tenant_dir"

    # Backup database
    echo "  → Dumping database..."
    docker exec "$db_container" sh -c \
        'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --all-databases --single-transaction' \
        > "$tenant_dir/database.sql" 2>/dev/null

    if [ -s "$tenant_dir/database.sql" ]; then
        echo -e "  ${GREEN}✓ Database dump: $(du -h "$tenant_dir/database.sql" | cut -f1)${NC}"
    else
        echo -e "  ${RED}✗ Database dump failed or empty${NC}"
        rm -f "$tenant_dir/database.sql"
    fi

    # Backup uploads
    echo "  → Backing up uploads..."
    docker cp "${wp_container}:/var/www/html/wp-content/uploads" \
        "$tenant_dir/uploads" 2>/dev/null || echo "  ⚠  No uploads found"

    if [ -d "$tenant_dir/uploads" ]; then
        UPLOAD_SIZE=$(du -sh "$tenant_dir/uploads" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓ Uploads: ${UPLOAD_SIZE}${NC}"
    fi

    # Backup wp-config
    echo "  → Backing up wp-config.php..."
    docker cp "${wp_container}:/var/www/html/wp-config.php" \
        "$tenant_dir/wp-config.php" 2>/dev/null || echo "  ⚠  wp-config not found"

    echo -e "${GREEN}✓ Tenant ${tenant} backup complete → ${tenant_dir}${NC}"
    echo ""
}

# ---- Main ----
if [ $# -gt 0 ]; then
    # Backup specific tenant
    backup_tenant "$1"
else
    # Backup all known tenants
    echo "Backing up all tenants..."
    echo ""
    backup_tenant "alpha"
    backup_tenant "beta"
fi

# ---- Summary ----
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅  Backup complete!                                   ║"
echo "║  Location: backups/$TIMESTAMP               ║"
echo "║  Total size: ${TOTAL_SIZE}                                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
