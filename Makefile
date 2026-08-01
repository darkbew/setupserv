# ==============================================================================
# Server Bootstrap Framework — Operator Makefile Interface
# ==============================================================================
#
# Description:
#   Provides standard CLI tasks wrapping platform lifecycle scripts and
#   Layer 3 application lifecycle targets.
#   Run 'make help' to list available targets.
#
# ==============================================================================

.PHONY: help platform platform-down platform-status platform-logs verify clean app-up app-down app-status app-logs

# Default target
.DEFAULT_GOAL := help

help: ## Show this Makefile help menu
	@printf '\n\033[1mServer Bootstrap Framework — Operator Interface\033[0m\n\n'
	@printf 'Usage:\n  make \033[36m<target>\033[0m\n\n'
	@printf 'Targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@printf '\n'

platform: ## Deploy Layer 2 Platform Infrastructure (Traefik & Socket Proxy)
	@bash scripts/deploy-platform.sh

platform-down: ## Stop Layer 2 Platform Containers
	@bash scripts/destroy-platform.sh

platform-status: ## Display Layer 2 Platform Status Matrix & Health
	@bash scripts/status-platform.sh

platform-logs: ## Tail Layer 2 Platform Container Logs
	@bash scripts/logs-platform.sh

verify: ## Run Layer 2 Platform Verification Matrix Check
	@bash scripts/verify-platform.sh

clean: ## Clean temporary operational files (preserves data/ & configs/)
	@rm -rf tmp/* logs/platform/*.log
	@printf '\033[0;32m[OK]\033[0m Cleaned temporary runtime files\n'

########################################
# Applications
########################################

app-up: ## Deploy Layer 3 Application (Usage: make app-up APP=<folder>)
	@if [ -z "$(APP)" ]; then \
		printf '\033[0;31m[ERROR]\033[0m APP variable is required. Usage: make app-up APP=<folder>\n' >&2; \
		exit 1; \
	fi
	@COMPOSE_FILE=""; \
	if [ -f "docker/apps/$(APP)/compose.yaml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yaml"; \
	elif [ -f "docker/apps/$(APP)/compose.yml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yml"; \
	else \
		printf '\033[0;31m[ERROR]\033[0m Application compose file not found: docker/apps/$(APP)/compose.yaml\n' >&2; \
		exit 1; \
	fi; \
	ENV_OPT=""; \
	if [ -f ".env" ]; then ENV_OPT="--env-file .env"; fi; \
	printf '\033[0;34m[INFO]\033[0m Deploying application $(APP)...\n'; \
	docker compose $$ENV_OPT -f $$COMPOSE_FILE up -d && \
	printf '\033[0;32m[OK]\033[0m Application $(APP) deployed successfully\n'

app-down: ## Stop Layer 3 Application (Usage: make app-down APP=<folder>)
	@if [ -z "$(APP)" ]; then \
		printf '\033[0;31m[ERROR]\033[0m APP variable is required. Usage: make app-down APP=<folder>\n' >&2; \
		exit 1; \
	fi
	@COMPOSE_FILE=""; \
	if [ -f "docker/apps/$(APP)/compose.yaml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yaml"; \
	elif [ -f "docker/apps/$(APP)/compose.yml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yml"; \
	else \
		printf '\033[0;31m[ERROR]\033[0m Application compose file not found: docker/apps/$(APP)/compose.yaml\n' >&2; \
		exit 1; \
	fi; \
	ENV_OPT=""; \
	if [ -f ".env" ]; then ENV_OPT="--env-file .env"; fi; \
	printf '\033[0;34m[INFO]\033[0m Stopping application $(APP)...\n'; \
	docker compose $$ENV_OPT -f $$COMPOSE_FILE down && \
	printf '\033[0;32m[OK]\033[0m Application $(APP) stopped successfully\n'

app-status: ## Display Layer 3 Application Status (Usage: make app-status APP=<folder>)
	@if [ -z "$(APP)" ]; then \
		printf '\033[0;31m[ERROR]\033[0m APP variable is required. Usage: make app-status APP=<folder>\n' >&2; \
		exit 1; \
	fi
	@COMPOSE_FILE=""; \
	if [ -f "docker/apps/$(APP)/compose.yaml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yaml"; \
	elif [ -f "docker/apps/$(APP)/compose.yml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yml"; \
	else \
		printf '\033[0;31m[ERROR]\033[0m Application compose file not found: docker/apps/$(APP)/compose.yaml\n' >&2; \
		exit 1; \
	fi; \
	ENV_OPT=""; \
	if [ -f ".env" ]; then ENV_OPT="--env-file .env"; fi; \
	docker compose $$ENV_OPT -f $$COMPOSE_FILE ps

app-logs: ## Tail Layer 3 Application Container Logs (Usage: make app-logs APP=<folder>)
	@if [ -z "$(APP)" ]; then \
		printf '\033[0;31m[ERROR]\033[0m APP variable is required. Usage: make app-logs APP=<folder>\n' >&2; \
		exit 1; \
	fi
	@COMPOSE_FILE=""; \
	if [ -f "docker/apps/$(APP)/compose.yaml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yaml"; \
	elif [ -f "docker/apps/$(APP)/compose.yml" ]; then \
		COMPOSE_FILE="docker/apps/$(APP)/compose.yml"; \
	else \
		printf '\033[0;31m[ERROR]\033[0m Application compose file not found: docker/apps/$(APP)/compose.yaml\n' >&2; \
		exit 1; \
	fi; \
	ENV_OPT=""; \
	if [ -f ".env" ]; then ENV_OPT="--env-file .env"; fi; \
	docker compose $$ENV_OPT -f $$COMPOSE_FILE logs -f
