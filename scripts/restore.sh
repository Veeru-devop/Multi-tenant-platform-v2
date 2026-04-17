#!/usr/bin/env bash
# ==============================================================
# WordPress Multitenancy Platform — Restore Script
# ==============================================================
# Restores a tenant from a backup directory.
# Usage: ./scripts/restore.sh <tenant-name> <backup-dir>
# Example: ./scripts/restore.sh alpha ./backups/20240115_120000
# ==============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---- Validate arguments ----
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <tenant-name> <backup-dir>${NC}"
    echo "  Example: $0 alpha ./backups/20240115_120000"
    echo ""
    echo "Available backups:"
    ls -d "$PROJECT_DIR/backups"/*/ 2>/dev/null || echo "  No backups found."
    exit 1
fi

TENANT="$1"
BACKUP_DIR="$2"
TENANT_BACKUP_DIR="$BACKUP_DIR/$TENANT"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  WordPress Multitenancy Platform — Restore              ║"
echo "║  Tenant: $TENANT"
echo "║  Backup: $BACKUP_DIR"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- Validate backup exists ----
if [ ! -d "$TENANT_BACKUP_DIR" ]; then
    echo -e "${RED}✗ Backup directory not found: $TENANT_BACKUP_DIR${NC}"
    exit 1
fi

DB_CONTAINER="db-${TENANT}"
WP_CONTAINER="wp-${TENANT}"

# ---- Check containers are running ----
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo -e "${RED}✗ Container ${DB_CONTAINER} is not running.${NC}"
    echo "  Start the platform first: make up"
    exit 1
fi

# ---- Confirm ----
echo -e "${YELLOW}⚠  WARNING: This will overwrite the current database and uploads for tenant: ${TENANT}${NC}"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ---- Restore database ----
if [ -f "$TENANT_BACKUP_DIR/database.sql" ]; then
    echo -e "${YELLOW}[1/2]${NC} Restoring database..."
    docker exec -i "$DB_CONTAINER" sh -c \
        'mariadb -u root -p"$MARIADB_ROOT_PASSWORD"' \
        < "$TENANT_BACKUP_DIR/database.sql"
    echo -e "${GREEN}✓ Database restored${NC}"
else
    echo -e "${YELLOW}⚠  No database.sql found in backup. Skipping DB restore.${NC}"
fi

# ---- Restore uploads ----
if [ -d "$TENANT_BACKUP_DIR/uploads" ]; then
    echo -e "${YELLOW}[2/2]${NC} Restoring uploads..."
    docker cp "$TENANT_BACKUP_DIR/uploads" \
        "${WP_CONTAINER}:/var/www/html/wp-content/"
    # Fix permissions
    docker exec "$WP_CONTAINER" chown -R www-data:www-data /var/www/html/wp-content/uploads
    echo -e "${GREEN}✓ Uploads restored${NC}"
else
    echo -e "${YELLOW}⚠  No uploads directory found in backup. Skipping.${NC}"
fi

# ---- Done ----
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅  Restore complete for tenant: ${TENANT}              "
echo "║                                                        ║"
echo "║  Verify: http://${TENANT}-localhost                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
