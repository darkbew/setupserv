#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Status Monitor
# ==============================================================================
#
# Description:
#   Displays live status matrix, container health checks, network attachments,
#   and exposed ports for Layer 2 Platform infrastructure.
#
# Usage:
#   sudo bash scripts/status-platform.sh
#
# Constraints:
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

set -Eeuo pipefail

# Resolve script location and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ANSI formatting
BOLD=$'\033[1m'
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

printf '\n'
printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
printf '%s  LAYER 2 PLATFORM INFRASTRUCTURE — STATUS MATRIX                             %s\n' "${BOLD}" "${NC}"
printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
printf '\n'

COMPOSE_BASE="${PROJECT_ROOT}/docker/platform/compose.yaml"
if [[ -f "${COMPOSE_BASE}" ]]; then
    docker compose -f "${COMPOSE_BASE}" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
else
    printf '  %s[ERROR]%s Compose file not found: %s\n' "${RED}" "${NC}" "${COMPOSE_BASE}"
    exit 1
fi

printf '\n'
printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
printf '%s  PLATFORM NETWORKS STATUS                                                    %s\n' "${BOLD}" "${NC}"
printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"

for net in "proxy-net" "backend-net" "monitoring-net"; do
    if docker network inspect "${net}" >/dev/null 2>&1; then
        printf '  %s[ACTIVE]%s Network: %-15s (Driver: bridge)\n' "${GREEN}" "${NC}" "${net}"
    else
        printf '  %s[MISSING]%s Network: %-14s (Not created)\n' "${RED}" "${NC}" "${net}"
    fi
done

printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
printf '\n'
