#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Destructor
# ==============================================================================
#
# Description:
#   Gracefully stops and removes Layer 2 platform containers across all Compose overlays.
#   Performs force cleanup of lingering platform containers to prevent name conflicts.
#   Does NOT delete persistent data in data/, configuration files in configs/,
#   or the global .env file.
#
# Usage:
#   bash scripts/destroy-platform.sh
#
# Constraints:
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

set -Eeuo pipefail

# Resolve script location and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source framework shared library if available
if [[ -f "${PROJECT_ROOT}/bootstrap/lib/common.sh" ]]; then
    # shellcheck source=../bootstrap/lib/common.sh
    source "${PROJECT_ROOT}/bootstrap/lib/common.sh"
else
    log_info()    { printf '\033[0;34m[INFO]\033[0m    %s\n' "$*"; }
    log_success() { printf '\033[0;32m[OK]\033[0m      %s\n' "$*"; }
    log_warn()    { printf '\033[1;33m[WARN]\033[0m    %s\n' "$*"; }
    log_error()   { printf '\033[0;31m[ERROR]\033[0m   %s\n' "$*" >&2; }
    log_section() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
fi

log_section "Stopping Layer 2 Platform Containers"

COMPOSE_BASE="${PROJECT_ROOT}/docker/platform/compose.yaml"
if [[ ! -f "${COMPOSE_BASE}" ]]; then
    log_error "Base platform compose specification not found: ${COMPOSE_BASE}"
    exit 1
fi

COMPOSE_ARGS=("-f" "${COMPOSE_BASE}")

if [[ -f "${PROJECT_ROOT}/docker/platform/compose.monitoring.yaml" ]]; then
    COMPOSE_ARGS+=("-f" "${PROJECT_ROOT}/docker/platform/compose.monitoring.yaml")
fi

if [[ -f "${PROJECT_ROOT}/docker/platform/compose.tunnel.yaml" ]]; then
    COMPOSE_ARGS+=("-f" "${PROJECT_ROOT}/docker/platform/compose.tunnel.yaml")
fi

if [[ -f "${PROJECT_ROOT}/docker/platform/compose.backup.yaml" ]]; then
    COMPOSE_ARGS+=("-f" "${PROJECT_ROOT}/docker/platform/compose.backup.yaml")
fi

if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    COMPOSE_ARGS=("--env-file" "${PROJECT_ROOT}/.env" "${COMPOSE_ARGS[@]}")
fi

log_info "Stopping Layer 2 platform containers with Docker Compose..."
docker compose "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

# Force cleanup of any lingering platform containers by name to prevent recreate conflicts
platform_containers=(
    "docker-socket-proxy"
    "traefik"
    "cloudflared"
    "prometheus"
    "grafana"
    "node-exporter"
    "uptime-kuma"
    "dozzle"
    "backup-worker"
)

for cname in "${platform_containers[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${cname}$"; then
        docker rm -f "${cname}" >/dev/null 2>&1 || true
    fi
done

log_success "Layer 2 platform containers stopped and removed"
log_info "Persistent data preserved in: ${PROJECT_ROOT}/data/"
