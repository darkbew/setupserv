# ==============================================================================
# Server Bootstrap Framework — Operator Makefile Interface
# ==============================================================================
#
# Description:
#   Provides standard CLI tasks wrapping platform lifecycle scripts.
#   Run 'make help' to list available targets.
#
# ==============================================================================

.PHONY: help platform platform-down platform-status platform-logs verify clean

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
