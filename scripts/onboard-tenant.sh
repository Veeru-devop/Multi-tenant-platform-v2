#!/usr/bin/env bash
# ==============================================================
# WordPress Multitenancy Platform — Onboard New Tenant
# ==============================================================
# Usage: ./scripts/onboard-tenant.sh <tenant-name> <domain>
# Example: ./scripts/onboard-tenant.sh gamma tenant-gamma.localhost
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
    echo -e "${RED}Usage: $0 <tenant-name> <domain>${NC}"
    echo "  Example: $0 gamma tenant-gamma.localhost"
    exit 1
fi

TENANT_NAME="$1"
TENANT_DOMAIN="$2"
TENANT_UPPER=$(echo "$TENANT_NAME" | tr '[:lower:]' '[:upper:]')

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Onboarding Tenant: $TENANT_NAME"
echo "║  Domain: $TENANT_DOMAIN"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- Generate passwords ----
generate_password() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1
}

DB_ROOT_PASS=$(generate_password)
DB_USER_PASS=$(generate_password)

# ---- Step 1: Add env vars to .env ----
echo -e "${YELLOW}[1/4]${NC} Adding environment variables..."

cat >> "$PROJECT_DIR/.env" << EOF

# ---- Tenant ${TENANT_UPPER} (auto-generated) ----
${TENANT_UPPER}_DB_ROOT_PASSWORD=${DB_ROOT_PASS}
${TENANT_UPPER}_DB_NAME=wp_${TENANT_NAME}
${TENANT_UPPER}_DB_USER=wp_${TENANT_NAME}_user
${TENANT_UPPER}_DB_PASSWORD=${DB_USER_PASS}
${TENANT_UPPER}_DOMAIN=${TENANT_DOMAIN}
${TENANT_UPPER}_WP_DEBUG=false
EOF

echo -e "${GREEN}✓ Environment variables added to .env${NC}"

# ---- Step 2: Generate docker-compose override ----
echo -e "${YELLOW}[2/4]${NC} Generating Docker Compose override..."

OVERRIDE_FILE="$PROJECT_DIR/docker-compose.tenant-${TENANT_NAME}.yml"

cat > "$OVERRIDE_FILE" << EOF
# Auto-generated tenant overlay for: ${TENANT_NAME}
# Usage: docker compose -f docker-compose.yml -f ${OVERRIDE_FILE##*/} up -d

services:
  wp-${TENANT_NAME}:
    image: wordpress:6-php8.2-apache
    container_name: wp-${TENANT_NAME}
    restart: unless-stopped
    environment:
      WORDPRESS_DB_HOST: db-${TENANT_NAME}:3306
      WORDPRESS_DB_NAME: \${${TENANT_UPPER}_DB_NAME:-wp_${TENANT_NAME}}
      WORDPRESS_DB_USER: \${${TENANT_UPPER}_DB_USER:-wp_${TENANT_NAME}_user}
      WORDPRESS_DB_PASSWORD: \${${TENANT_UPPER}_DB_PASSWORD}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_DEBUG', \${${TENANT_UPPER}_WP_DEBUG:-false});
        define('DISALLOW_FILE_EDIT', true);
        define('WP_AUTO_UPDATE_CORE', false);
    volumes:
      - wp_${TENANT_NAME}_data:/var/www/html
      - wp_${TENANT_NAME}_uploads:/var/www/html/wp-content/uploads
    networks:
      - frontend
      - backend-${TENANT_NAME}
    depends_on:
      db-${TENANT_NAME}:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/wp-admin/install.php"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  db-${TENANT_NAME}:
    image: mariadb:11.2
    container_name: db-${TENANT_NAME}
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: \${${TENANT_UPPER}_DB_ROOT_PASSWORD}
      MARIADB_DATABASE: \${${TENANT_UPPER}_DB_NAME:-wp_${TENANT_NAME}}
      MARIADB_USER: \${${TENANT_UPPER}_DB_USER:-wp_${TENANT_NAME}_user}
      MARIADB_PASSWORD: \${${TENANT_UPPER}_DB_PASSWORD}
    volumes:
      - db_${TENANT_NAME}_data:/var/lib/mysql
    networks:
      - backend-${TENANT_NAME}
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

networks:
  frontend:
    name: wp-frontend
  backend-${TENANT_NAME}:
    name: wp-backend-${TENANT_NAME}
    driver: bridge
    internal: true

volumes:
  wp_${TENANT_NAME}_data:
    name: wp_${TENANT_NAME}_data
  wp_${TENANT_NAME}_uploads:
    name: wp_${TENANT_NAME}_uploads
  db_${TENANT_NAME}_data:
    name: db_${TENANT_NAME}_data
EOF

echo -e "${GREEN}✓ Docker Compose overlay created: ${OVERRIDE_FILE##*/}${NC}"

# ---- Step 3: Generate nginx server block ----
echo -e "${YELLOW}[3/4]${NC} Generating Nginx configuration snippet..."

NGINX_SNIPPET="$PROJECT_DIR/nginx/tenant-${TENANT_NAME}.conf.snippet"

cat > "$NGINX_SNIPPET" << EOF
    # ---- Tenant ${TENANT_NAME} (auto-generated) ----
    # Add this upstream to the http block:
    #   upstream wp_${TENANT_NAME} {
    #       server wp-${TENANT_NAME}:80;
    #   }
    #
    # Add this server block inside the http block:

    server {
        listen 80;
        server_name ${TENANT_DOMAIN};

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        location = /wp-login.php {
            limit_req zone=wp_login burst=3 nodelay;
            proxy_pass http://wp_${TENANT_NAME};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location = /xmlrpc.php {
            deny all;
            return 403;
        }

        location ~* /(?:wp-config\.php|readme\.html|license\.txt) {
            deny all;
            return 404;
        }

        location / {
            limit_req zone=general burst=20 nodelay;
            proxy_pass http://wp_${TENANT_NAME};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
        }
    }
EOF

echo -e "${GREEN}✓ Nginx snippet created: ${NGINX_SNIPPET##*/}${NC}"

# ---- Step 4: Summary ----
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ✅  Tenant ${TENANT_NAME} onboarding files generated!  "
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}Manual steps required:${NC}"
echo ""
echo "  1. Add the Nginx upstream & server block from:"
echo "     nginx/tenant-${TENANT_NAME}.conf.snippet"
echo "     into nginx/nginx.conf"
echo ""
echo "  2. Add to your hosts file:"
echo "     127.0.0.1  ${TENANT_DOMAIN}"
echo ""
echo "  3. Start the new tenant:"
echo "     docker compose -f docker-compose.yml \\"
echo "       -f docker-compose.tenant-${TENANT_NAME}.yml \\"
echo "       -f docker-compose.monitoring.yml up -d"
echo ""
echo "  4. Visit: http://${TENANT_DOMAIN}"
echo ""
