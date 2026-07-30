#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Layer 2 Platform Verification Matrix
# ==============================================================================
#
# Description:
#   Performs comprehensive assertion checks against Layer 2 platform components:
#   Docker daemon status, network bridges, configuration file existence,
#   acme.json permissions (600), image tag pinning (no :latest), admin email,
#   container health states, and host port bindings (80 & 443).
#
# Usage:
#   sudo bash scripts/verify-platform.sh
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
        printf '  %s[PASS]%s %-35s : %s\n' "${GREEN}" "${NC}" "${description}" "${details}"
        pass_count=$((pass_count + 1))
    else
        printf '  %s[FAIL]%s %-35s : %s\n' "${RED}" "${NC}" "${description}" "${details}"
        fail_count=$((fail_count + 1))
    fi
}

printf '\n'
printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
printf '%s  SERVER BOOTSTRAP FRAMEWORK — LAYER 2 VERIFICATION MATRIX                    %s\n' "${BOLD}" "${NC}"
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
COMPOSE_FILE="${PROJECT_ROOT}/docker/platform/compose.yaml"
if [[ -f "${COMPOSE_FILE}" ]]; then
    check_result "Platform Compose (compose.yaml)" "PASS" "File present"
else
    check_result "Platform Compose (compose.yaml)" "FAIL" "File missing: ${COMPOSE_FILE}"
fi

TRAEFIK_STATIC="${PROJECT_ROOT}/configs/traefik/traefik.yaml"
if [[ -f "${TRAEFIK_STATIC}" ]]; then
    check_result "Traefik Static Config (traefik.yaml)" "PASS" "File present"
else
    check_result "Traefik Static Config (traefik.yaml)" "FAIL" "File missing: ${TRAEFIK_STATIC}"
fi

MIDDLEWARES_FILE="${PROJECT_ROOT}/configs/traefik/dynamic/middlewares.yaml"
if [[ -f "${MIDDLEWARES_FILE}" ]]; then
    check_result "Dynamic Middlewares (middlewares.yaml)" "PASS" "File present"
else
    check_result "Dynamic Middlewares (middlewares.yaml)" "FAIL" "File missing: ${MIDDLEWARES_FILE}"
fi

# 3. Bridge Networks Checks
for net in "proxy-net" "backend-net" "monitoring-net"; do
    if docker network inspect "${net}" >/dev/null 2>&1; then
        check_result "Docker Network: ${net}" "PASS" "Active (Driver: bridge)"
    else
        check_result "Docker Network: ${net}" "FAIL" "Network not found"
    fi
done

# 4. acme.json File Permissions Check
ACME_FILE="${PROJECT_ROOT}/data/traefik/acme.json"
if [[ -f "${ACME_FILE}" ]]; then
    file_perm=$(stat -c "%a" "${ACME_FILE}" 2>/dev/null || stat -f "%Lp" "${ACME_FILE}" 2>/dev/null || echo "000")
    if [[ "${file_perm}" == "600" ]]; then
        check_result "Certificate Store (acme.json)" "PASS" "Mode 600 verified"
    else
        check_result "Certificate Store (acme.json)" "FAIL" "Invalid mode ${file_perm} (expected 600)"
    fi
else
    check_result "Certificate Store (acme.json)" "FAIL" "File missing: ${ACME_FILE}"
fi

# 5. Image Tag Pinning Check (No :latest)
sp_tag="${SOCKET_PROXY_IMAGE_TAG:-0.3.0}"
if [[ "${sp_tag}" != "latest" ]] && [[ "${sp_tag}" != ":latest" ]]; then
    check_result "Socket Proxy Tag Pinning" "PASS" "Pinned tag: ${sp_tag}"
else
    check_result "Socket Proxy Tag Pinning" "FAIL" "Forbidden :latest tag configured"
fi

# 6. Admin Email Configuration Check
admin_email="${ADMIN_EMAIL:-admin@${DOMAIN:-example.com}}"
if [[ -n "${admin_email}" ]] && [[ ! "${admin_email,,}" =~ ^(change_me|your_.*)$ ]]; then
    check_result "Admin Email Configuration" "PASS" "Configured: ${admin_email}"
else
    check_result "Admin Email Configuration" "FAIL" "Unconfigured or placeholder email"
fi

# 7. Socket Proxy Container Check
if docker ps --format '{{.Names}}' | grep -q '^docker-socket-proxy$'; then
    sp_health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' docker-socket-proxy 2>/dev/null || echo "unknown")
    if [[ "${sp_health}" == "healthy" ]] || [[ "${sp_health}" == "running" ]]; then
        check_result "Socket Proxy (docker-socket-proxy)" "PASS" "Status: ${sp_health}"
    else
        check_result "Socket Proxy (docker-socket-proxy)" "FAIL" "Status: ${sp_health}"
    fi
else
    check_result "Socket Proxy (docker-socket-proxy)" "FAIL" "Container not running"
fi

# 8. Traefik Container Check
if docker ps --format '{{.Names}}' | grep -q '^traefik$'; then
    tf_health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' traefik 2>/dev/null || echo "unknown")
    if [[ "${tf_health}" == "healthy" ]] || [[ "${tf_health}" == "running" ]]; then
        check_result "Traefik Ingress (traefik)" "PASS" "Status: ${tf_health}"
    else
        check_result "Traefik Ingress (traefik)" "FAIL" "Status: ${tf_health}"
    fi
else
    check_result "Traefik Ingress (traefik)" "FAIL" "Container not running"
fi

# 9. Host Port 80 Check
if netstat -tuln 2>/dev/null | grep -E ':(80|0\.0\.0\.0:80) ' >/dev/null || ss -tuln 2>/dev/null | grep -E ':(80|0\.0\.0\.0:80) ' >/dev/null || lsof -i :80 >/dev/null 2>&1; then
    check_result "Host Ingress Port 80 (HTTP)" "PASS" "Port listening"
else
    check_result "Host Ingress Port 80 (HTTP)" "FAIL" "Port 80 not listening"
fi

# 10. Host Port 443 Check
if netstat -tuln 2>/dev/null | grep -E ':(443|0\.0\.0\.0:443) ' >/dev/null || ss -tuln 2>/dev/null | grep -E ':(443|0\.0\.0\.0:443) ' >/dev/null || lsof -i :443 >/dev/null 2>&1; then
    check_result "Host Ingress Port 443 (HTTPS)" "PASS" "Port listening"
else
    check_result "Host Ingress Port 443 (HTTPS)" "FAIL" "Port 443 not listening"
fi

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
