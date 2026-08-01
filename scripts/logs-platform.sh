#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Log Viewer
# ==============================================================================
#
# Description:
#   Tails combined logs for Layer 2 platform containers via Docker Compose logs -f.
#
# Usage:
#   sudo bash scripts/logs-platform.sh [SERVICE_NAME]
#
# Constraints:
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

set -Eeuo pipefail

# Resolve script location and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMPOSE_BASE="${PROJECT_ROOT}/docker/platform/compose.yaml"
if [[ ! -f "${COMPOSE_BASE}" ]]; then
    printf 'ERROR: Base platform compose specification not found: %s\n' "${COMPOSE_BASE}" >&2
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

if [[ $# -gt 0 ]]; then
    exec docker compose "${COMPOSE_ARGS[@]}" logs -f "$1"
else
    exec docker compose "${COMPOSE_ARGS[@]}" logs -f
fi
