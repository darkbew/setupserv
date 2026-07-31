#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Verification Matrix
# ==============================================================================
#
# Description:
#   Comprehensive post-deployment verification for Cloudflare Tunnel Ingress Architecture.
#   Validates Docker Engine, bridge network isolation, configuration assets,
#   Cloudflare Tunnel agent readiness, Traefik internal HTTP routing, container health matrix,
#   and host port isolation guards (verifying ports 80/443 are NOT exposed to host).
#
# Usage:
#   bash scripts/verify-platform.sh
#
# Exit Codes:
#   0 — All verification checks passed
#   1 — One or more verification checks failed
#
# ==============================================================================

set -Eeuo pipefail

# Resolve script location and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load active environment variables if available
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

# ANSI Formatting
BOLD=$'\033[1m'
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

pass_count=0
fail_count=0

check_result() {
    local description="$1"
    local status="$2"
    local details="${3:-}"

    if [[ "${status}" == "PASS" ]]; then
        printf '  %s[PASS]%s %-44s : %s\n' "${GREEN}" "${NC}" "${description}" "${details}"
        pass_count=$((pass_count + 1))
    else
        printf '  %s[FAIL]%s %-44s : %s\n' "${RED}" "${NC}" "${description}" "${details}"
        fail_count=$((fail_count + 1))
    fi
}

printf '\n'
printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
printf '%s  SERVER BOOTSTRAP FRAMEWORK — LAYER 2 CLOUDFLARE TUNNEL VERIFICATION MATRIX  %s\n' "${BOLD}" "${NC}"
printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
printf '\n'

# 1. Docker Daemon Check
if docker info >/dev/null 2>&1; then
    docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "active")
    check_result "Docker Daemon Engine" "PASS" "Running (v${docker_ver})"
else
    check_result "Docker Daemon Engine" "FAIL" "Docker daemon unreachable or stopped"
fi

# 2. Configuration Files Existence Checks
for cfg in \
    "${PROJECT_ROOT}/docker/platform/compose.yaml" \
    "${PROJECT_ROOT}/configs/traefik/traefik.yaml" \
    "${PROJECT_ROOT}/configs/traefik/dynamic/middlewares.yaml" \
    "${PROJECT_ROOT}/configs/prometheus/prometheus.yaml" \
    "${PROJECT_ROOT}/configs/grafana/provisioning/datasources/datasources.yaml" \
    "${PROJECT_ROOT}/configs/grafana/provisioning/dashboards/dashboards.yaml"
do
    bname="$(basename "${cfg}")"
    if [[ -f "${cfg}" ]]; then
        check_result "Config File: ${bname}" "PASS" "Present"
    else
        check_result "Config File: ${bname}" "FAIL" "Missing file: ${cfg}"
    fi
done

# 3. Bridge Networks Checks
for net in "proxy-net" "backend-net" "monitoring-net"; do
    if docker network inspect "${net}" >/dev/null 2>&1; then
        check_result "Docker Network: ${net}" "PASS" "Active (Driver: bridge)"
    else
        check_result "Docker Network: ${net}" "FAIL" "Network not found"
    fi
done

# 4. Image Tag Pinning Check (No :latest)
sp_tag="${SOCKET_PROXY_IMAGE_TAG:-0.3.0}"
if [[ "${sp_tag}" != "latest" ]] && [[ "${sp_tag}" != ":latest" ]]; then
    check_result "Socket Proxy Tag Pinning" "PASS" "Pinned tag: ${sp_tag}"
else
    check_result "Socket Proxy Tag Pinning" "FAIL" "Forbidden :latest tag configured"
fi

# 5. Cloudflare Tunnel Token Configuration Check
cf_token="${CLOUDFLARE_TUNNEL_TOKEN:-}"
if [[ -n "${cf_token}" ]] && [[ "${cf_token}" != "CHANGE_ME" ]]; then
    check_result "Cloudflare Tunnel Token" "PASS" "Configured"
else
    check_result "Cloudflare Tunnel Token" "FAIL" "Unconfigured or placeholder token"
fi

# 6. Layer 2 Platform Container Health Matrix (8 Core Containers)
check_container_health() {
    local cname="$1"
    local display_name="$2"

    if docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
        chealth=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${cname}" 2>/dev/null || echo "unknown")
        if [[ "${chealth}" == "healthy" ]] || [[ "${chealth}" == "running" ]]; then
            check_result "Container: ${display_name}" "PASS" "Status: ${chealth}"
        else
            check_result "Container: ${display_name}" "FAIL" "Status: ${chealth}"
        fi
    else
        check_result "Container: ${display_name}" "FAIL" "Container not running"
    fi
}

check_container_health "docker-socket-proxy" "Socket Proxy"
check_container_health "traefik" "Traefik Ingress"
check_container_health "cloudflared" "Cloudflare Tunnel Agent"
check_container_health "prometheus" "Prometheus"
check_container_health "grafana" "Grafana"
check_container_health "node-exporter" "Node Exporter"
check_container_health "uptime-kuma" "Uptime Kuma"
check_container_health "dozzle" "Dozzle Log Viewer"

# 7. Cloudflare Tunnel Agent Readiness Verification
if docker inspect cloudflared --format='{{.State.Running}}' 2>/dev/null | grep -q "true"; then
    if docker exec traefik wget -q -O - http://cloudflared:2000/ready >/dev/null 2>&1 || docker logs cloudflared 2>&1 | grep -iq "Registered tunnel connection"; then
        check_result "Cloudflare Tunnel Connection" "PASS" "Agent connected to Cloudflare Edge"
    else
        cf_token="${CLOUDFLARE_TUNNEL_TOKEN:-}"
        if [[ -z "${cf_token}" ]] || [[ "${cf_token}" == "CHANGE_ME" ]]; then
            check_result "Cloudflare Tunnel Connection" "FAIL" "Placeholder token detected in .env — set CLOUDFLARE_TUNNEL_TOKEN to your Cloudflare Zero Trust token"
        else
            check_result "Cloudflare Tunnel Connection" "FAIL" "Tunnel agent running but edge connection failed — verify token validity in Cloudflare Zero Trust dashboard"
        fi
    fi
else
    check_result "Cloudflare Tunnel Connection" "FAIL" "Tunnel container not running"
fi

# 8. Traefik Internal HTTP Routing Verification
if docker exec traefik traefik healthcheck --ping >/dev/null 2>&1; then
    check_result "Traefik Internal HTTP Router" "PASS" "Ping healthcheck responsive"
else
    check_result "Traefik Internal HTTP Router" "FAIL" "Traefik ping check non-responsive"
fi

# 9. Host Port Isolation Guard (Ports 80 & 443 must NOT be bound to host)
check_host_port_unbound() {
    local port="$1"
    local bound=false
    local proc_info=""

    if command -v ss >/dev/null 2>&1; then
        proc_info=$(ss -tulnp 2>/dev/null | grep -E ":${port}\s" || true)
    elif command -v netstat >/dev/null 2>&1; then
        proc_info=$(netstat -tulnp 2>/dev/null | grep -E ":${port}\s" || true)
    fi

    if [[ -n "${proc_info}" ]]; then
        bound=true
    fi

    if [[ "${bound}" == "false" ]]; then
        check_result "Host Security: Port ${port} Isolated" "PASS" "Port not exposed to host"
    else
        check_result "Host Security: Port ${port} Isolated" "FAIL" "Port ${port} is listening on host (run 'make platform-down && make platform' to recreate containers without host ports)"
    fi
}

check_host_port_unbound 80
check_host_port_unbound 443

printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
total_checks=$((pass_count + fail_count))
if [[ "${fail_count}" -eq 0 ]]; then
    printf '  %sVerification Result: ALL CHECKS PASSED (%d/%d)%s\n' "${GREEN}" "${pass_count}" "${total_checks}" "${NC}"
    printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '\n'
    exit 0
else
    printf '  %sVerification Result: FAILED (%d/%d checks passed)%s\n' "${RED}" "${pass_count}" "${total_checks}" "${NC}"
    printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '\n'
    exit 1
fi
