# ==============================================================
# WordPress Multitenancy Platform — Makefile
# ==============================================================
# One-command operations for the platform.
# ==============================================================

.PHONY: up down restart logs status backup setup clean help

COMPOSE_BASE = docker compose -f docker-compose.yml
COMPOSE_FULL = docker compose -f docker-compose.yml -f docker-compose.monitoring.yml

## ---- Primary Commands ----

help: ## Show this help message
	@echo ""
	@echo "WordPress Multitenancy Platform"
	@echo "================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Initial setup: generate .env, validate Docker
	@bash scripts/setup.sh

up: ## Start ALL services (platform + monitoring)
	$(COMPOSE_FULL) up -d
	@echo ""
	@echo "✅  Platform is starting!"
	@echo ""
	@echo "  WordPress Tenant Alpha:  http://tenant-alpha.localhost"
	@echo "  WordPress Tenant Beta:   http://tenant-beta.localhost"
	@echo "  Grafana Dashboard:       http://localhost:3000"
	@echo "  Prometheus:              http://localhost:9090"
	@echo ""
	@echo "  Run 'make status' to check container health."

up-wp: ## Start WordPress services only (no monitoring)
	$(COMPOSE_BASE) up -d

down: ## Stop ALL services
	$(COMPOSE_FULL) down

restart: ## Restart ALL services
	$(COMPOSE_FULL) down
	$(COMPOSE_FULL) up -d

logs: ## Follow logs for all services
	$(COMPOSE_FULL) logs -f

logs-wp: ## Follow logs for WordPress services only
	$(COMPOSE_BASE) logs -f

status: ## Show status of all containers
	$(COMPOSE_FULL) ps

backup: ## Backup all tenants
	@bash scripts/backup.sh

restore: ## Restore a tenant (usage: make restore TENANT=alpha BACKUP_DIR=./backups/2024xxxx)
	@bash scripts/restore.sh $(TENANT) $(BACKUP_DIR)

onboard: ## Onboard a new tenant (usage: make onboard TENANT=gamma DOMAIN=tenant-gamma.localhost)
	@bash scripts/onboard-tenant.sh $(TENANT) $(DOMAIN)

clean: ## Stop all services and remove volumes (⚠️  DESTRUCTIVE)
	$(COMPOSE_FULL) down -v --remove-orphans
	@echo "⚠️  All volumes removed. Data is gone."

validate: ## Validate Docker Compose configuration
	$(COMPOSE_FULL) config --quiet && echo "✅ Configuration is valid"

shell-alpha: ## Open a shell in Tenant Alpha WordPress container
	docker exec -it wp-alpha bash

shell-beta: ## Open a shell in Tenant Beta WordPress container
	docker exec -it wp-beta bash

db-alpha: ## Open MariaDB CLI for Tenant Alpha
	docker exec -it db-alpha mariadb -u root -p

db-beta: ## Open MariaDB CLI for Tenant Beta
	docker exec -it db-beta mariadb -u root -p
