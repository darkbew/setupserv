#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Deployer
# ==============================================================================
#
# Description:
#   Initializes host data directories, sets 600 permissions on acme.json,
#   resolves dynamic ADMIN_EMAIL, verifies required configuration files,
#   validates tokens/secrets, verifies host ingress ports 80/443,
#   creates required external Docker bridge networks (proxy-net, backend-net,
#   monitoring-net), constructs compose overlay chain, and launches Layer 2
#   platform services (Traefik v3, Socket Proxy, Cloudflared, Prometheus, Grafana,
#   Node Exporter, Uptime Kuma, Dozzle).
#
# Usage:
#   sudo bash scripts/deploy-platform.sh
#
# Constraints:
#   - Must run with root / sudo privileges
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
    # Fallback logging helpers if library not sourced directly
    log_info()    { printf '\033[0;34m[INFO]\033[0m    %s\n' "$*"; }
    log_success() { printf '\033[0;32m[OK]\033[0m      %s\n' "$*"; }
    log_warn()    { printf '\033[1;33m[WARN]\033[0m    %s\n' "$*"; }
    log_error()   { printf '\033[0;31m[ERROR]\033[0m   %s\n' "$*" >&2; }
    log_section() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
fi

# Load active environment variables
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
    log_info "Loaded active configuration: ${PROJECT_ROOT}/.env"
else
    log_warn "No .env file found at ${PROJECT_ROOT}/.env — using defaults"
fi

# Resolve effective ADMIN_EMAIL (fallback to admin@${DOMAIN} if empty or placeholder)
raw_admin_email="${ADMIN_EMAIL:-}"
if [[ -z "${raw_admin_email}" ]] || [[ "${raw_admin_email,,}" =~ ^(admin@example\.com|change_me|your_.*)$ ]]; then
    export ADMIN_EMAIL="admin@${DOMAIN:-example.com}"
else
    export ADMIN_EMAIL="${raw_admin_email}"
fi
export SOCKET_PROXY_IMAGE_TAG="${SOCKET_PROXY_IMAGE_TAG:-0.3.0}"

log_info "Effective Let's Encrypt Admin Email: ${ADMIN_EMAIL}"
log_info "Effective Socket Proxy Image Tag: ${SOCKET_PROXY_IMAGE_TAG}"

log_section "Initializing Layer 2 Platform Infrastructure"

# Ensure required directory structure exists
mkdir -p "${PROJECT_ROOT}/configs/traefik/dynamic"
mkdir -p "${PROJECT_ROOT}/configs/prometheus"
mkdir -p "${PROJECT_ROOT}/configs/grafana/provisioning/datasources"
mkdir -p "${PROJECT_ROOT}/configs/grafana/provisioning/dashboards/default"
mkdir -p "${PROJECT_ROOT}/data/traefik"
mkdir -p "${PROJECT_ROOT}/data/prometheus/data"
mkdir -p "${PROJECT_ROOT}/data/grafana/data"
mkdir -p "${PROJECT_ROOT}/data/uptime-kuma/data"
mkdir -p "${PROJECT_ROOT}/logs/platform"

# Enforce correct container ownership on data directories to prevent permission errors
if command -v chown >/dev/null 2>&1; then
    chown -R 65534:65534 "${PROJECT_ROOT}/data/prometheus/data" 2>/dev/null || true
    chown -R 472:0 "${PROJECT_ROOT}/data/grafana/data" 2>/dev/null || true
fi


# Verify mandatory configuration files existence
log_info "Verifying required configuration files..."
missing_cfg=0
req_configs=(
    "${PROJECT_ROOT}/configs/traefik/traefik.yaml"
    "${PROJECT_ROOT}/configs/traefik/dynamic/middlewares.yaml"
    "${PROJECT_ROOT}/configs/traefik/dynamic/tls-options.yaml"
    "${PROJECT_ROOT}/configs/prometheus/prometheus.yaml"
    "${PROJECT_ROOT}/configs/grafana/provisioning/datasources/datasources.yaml"
    "${PROJECT_ROOT}/configs/grafana/provisioning/dashboards/dashboards.yaml"
)

for cfg in "${req_configs[@]}"; do
    if [[ ! -f "${cfg}" ]]; then
        log_error "Missing required configuration file: ${cfg}"
        missing_cfg=$((missing_cfg + 1))
    fi
done

if [[ "${missing_cfg}" -gt 0 ]]; then
    log_error "Deployment aborted due to missing configuration files."
    exit 1
fi
log_success "All required configuration files verified"

# Validate Cloudflare Tunnel Token
cf_token="${CLOUDFLARE_TUNNEL_TOKEN:-}"
if [[ -z "${cf_token}" ]] || [[ "${cf_token}" == "CHANGE_ME" ]]; then
    log_error "CLOUDFLARE_TUNNEL_TOKEN is unconfigured or set to placeholder in .env!"
    log_error "Please set a valid Cloudflare Tunnel Token before deploying."
    exit 1
fi
log_success "Cloudflare Tunnel Token validated"

# Initialize acme.json with strict 600 permissions
ACME_FILE="${PROJECT_ROOT}/data/traefik/acme.json"
if [[ ! -f "${ACME_FILE}" ]]; then
    touch "${ACME_FILE}"
    log_info "Created certificate store: ${ACME_FILE}"
fi
chmod 600 "${ACME_FILE}"
log_success "Verified permissions (600) on ${ACME_FILE}"

# Host Ingress Port Conflict Detection (TCP 80 & 443)
check_port_conflict() {
    local port="$1"
    local pinfo=""

    if command -v ss >/dev/null 2>&1; then
        pinfo=$(ss -tulnp 2>/dev/null | grep -E ":${port}\s" || true)
    elif command -v netstat >/dev/null 2>&1; then
        pinfo=$(netstat -tulnp 2>/dev/null | grep -E ":${port}\s" || true)
    elif command -v lsof >/dev/null 2>&1; then
        pinfo=$(lsof -i ":${port}" 2>/dev/null | grep LISTEN || true)
    fi

    if [[ -n "${pinfo}" ]]; then
        local proc_name="unknown"
        local pid="unknown"

        if [[ "${pinfo}" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
            proc_name="${BASH_REMATCH[1]}"
            pid="${BASH_REMATCH[2]}"
        elif [[ "${pinfo}" =~ ([0-9]+)/([a-zA-Z0-9_-]+) ]]; then
            pid="${BASH_REMATCH[1]}"
            proc_name="${BASH_REMATCH[2]}"
        elif [[ "${pinfo}" =~ ([a-zA-Z0-9_-]+)[[:space:]]+([0-9]+) ]]; then
            proc_name="${BASH_REMATCH[1]}"
            pid="${BASH_REMATCH[2]}"
        fi

        # Allow if owned by Docker daemon proxy / active Traefik container
        if [[ "${proc_name}" == "docker-proxy" ]] || [[ "${proc_name}" == "traefik" ]]; then
            log_info "Port ${port} is currently bound by platform ingress (${proc_name})"
            return 0
        fi

        log_error "Port ${port} already used by ${proc_name} (PID ${pid})"
        log_error "Resolve the conflict before deploying Layer 2."
        return 1
    fi

    return 0
}

log_info "Verifying host ingress port availability (80 & 443)..."
if ! check_port_conflict 80 || ! check_port_conflict 443; then
    log_error "Aborting deployment due to host port conflict."
    exit 1
fi
log_success "Host ports 80 and 443 available"

# Idempotently create external Docker bridge networks
ensure_network() {
    local net_name="$1"
    if ! docker network inspect "${net_name}" >/dev/null 2>&1; then
        docker network create --driver bridge "${net_name}" >/dev/null
        log_success "Created Docker bridge network: ${net_name}"
    else
        log_info "Docker bridge network already active: ${net_name}"
    fi
}

ensure_network "proxy-net"
ensure_network "backend-net"
ensure_network "monitoring-net"

# Construct Docker Compose file chain
COMPOSE_BASE="${PROJECT_ROOT}/docker/platform/compose.yaml"
if [[ ! -f "${COMPOSE_BASE}" ]]; then
    log_error "Base platform compose specification not found: ${COMPOSE_BASE}"
    exit 1
fi

COMPOSE_ARGS=("-f" "${COMPOSE_BASE}")

if [[ -f "${PROJECT_ROOT}/docker/platform/compose.monitoring.yaml" ]]; then
    COMPOSE_ARGS+=("-f" "${PROJECT_ROOT}/docker/platform/compose.monitoring.yaml")
    log_info "Added Compose Overlay: compose.monitoring.yaml"
fi

if [[ -f "${PROJECT_ROOT}/docker/platform/compose.tunnel.yaml" ]]; then
    COMPOSE_ARGS+=("-f" "${PROJECT_ROOT}/docker/platform/compose.tunnel.yaml")
    log_info "Added Compose Overlay: compose.tunnel.yaml"
fi

expected_containers=(
    "docker-socket-proxy"
    "traefik"
    "cloudflared"
    "prometheus"
    "grafana"
    "node-exporter"
    "uptime-kuma"
    "dozzle"
)

# Launch Layer 2 Containers via Docker Compose
log_info "Deploying Layer 2 platform containers with Docker Compose..."
if docker compose "${COMPOSE_ARGS[@]}" up -d; then
    log_success "Layer 2 containers started successfully"
else
    log_error "Failed to deploy Layer 2 platform containers"
    exit 1
fi

# Wait for containers to become healthy before verification
log_info "Waiting for platform containers to pass health checks..."
max_wait=60
elapsed=0
all_healthy=false

while [[ "${elapsed}" -lt "${max_wait}" ]]; do
    healthy=true

    for cname in "${expected_containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
            status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${cname}" 2>/dev/null || echo "unknown")
            if [[ "${status}" != "healthy" ]] && [[ "${status}" != "running" ]]; then
                healthy=false
                break
            fi
        else
            healthy=false
            break
        fi
    done

    if [[ "${healthy}" == "true" ]]; then
        all_healthy=true
        break
    fi

    sleep 2
    elapsed=$((elapsed + 2))
done

if [[ "${all_healthy}" == "true" ]]; then
    log_success "All 8 Layer 2 platform containers healthy (${elapsed}s)"
else
    log_warn "Some containers not yet healthy after ${max_wait}s — proceeding with verification"
fi

# Invoke Platform Verification Script
VERIFY_SCRIPT="${SCRIPT_DIR}/verify-platform.sh"
if [[ -f "${VERIFY_SCRIPT}" ]]; then
    log_info "Executing Layer 2 post-deployment verification matrix..."
    if bash "${VERIFY_SCRIPT}"; then
        log_success "Layer 2 Platform Deployment Verified Successfully"
        exit 0
    else
        log_error "Layer 2 verification check failed"
        exit 1
    fi
else
    log_warn "Verification script not found: ${VERIFY_SCRIPT}"
    exit 0
fi
