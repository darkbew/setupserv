#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Destructor
# ==============================================================================
#
# Description:
#   Gracefully stops and removes Layer 2 platform containers using Docker Compose down.
#   Does NOT delete persistent data in data/, configuration files in configs/,
#   or the global .env file.
#
# Usage:
#   sudo bash scripts/destroy-platform.sh
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

if docker compose -f "${COMPOSE_BASE}" down; then
    log_success "Layer 2 platform containers stopped and removed"
    log_info "Persistent data preserved in: ${PROJECT_ROOT}/data/"
else
    log_error "Failed to cleanly stop Layer 2 containers"
    exit 1
fi
