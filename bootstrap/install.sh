#!/usr/bin/env bash
# ==============================================================================
# Mitseri Platform — Bootstrap Installer
# ==============================================================================
#
# Master orchestrator for server bootstrap.
# Runs all bootstrap scripts in the correct order.
#
# This is the SINGLE ENTRY POINT for server setup:
#   sudo bash bootstrap/install.sh
#
# Features:
#   - Runs all bootstrap steps (00–06) in sequence
#   - Stops immediately on any failure
#   - Supports --dry-run mode (or DRY_RUN=true)
#   - Logs everything to /var/log/mitseri/
#   - Fully idempotent — safe to re-run
#   - Prints summary with next steps
#
# Usage:
#   sudo bash bootstrap/install.sh              # Production run
#   sudo bash bootstrap/install.sh --dry-run    # Simulate only
#   DRY_RUN=true sudo bash bootstrap/install.sh # Simulate only (env)
#
# ==============================================================================

# === Resolve Script Location ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# === Parse Arguments ===
DRY_RUN="${DRY_RUN:-false}"

usage() {
    printf 'Usage: sudo bash %s [OPTIONS]\n\n' "$0"
    printf 'Options:\n'
    printf '  --dry-run    Simulate without making changes\n'
    printf '  --help, -h   Show this help message\n'
    printf '\n'
    printf 'Environment:\n'
    printf '  DRY_RUN=true   Same as --dry-run\n'
    printf '\n'
}

for arg in "$@"; do
    case "${arg}" in
        --dry-run)
            DRY_RUN="true"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "${arg}" >&2
            usage
            exit 1
            ;;
    esac
done

export DRY_RUN
export PROJECT_ROOT
export LOG_DIR="/var/log/mitseri"

# === Source Common Library ===
# shellcheck source=lib/common.sh
source "${BOOTSTRAP_DIR}/lib/common.sh"

# === Load Environment ===
load_env "${PROJECT_ROOT}/.env"

# Share log file with all child scripts
export LOG_FILE

# ==============================================================================
# STEP RUNNER
# ==============================================================================

run_step() {
    local step_number="$1"
    local total_steps="$2"
    local step_name="$3"
    local script_file="$4"

    local script_path="${BOOTSTRAP_DIR}/${script_file}"

    if [[ ! -f "${script_path}" ]]; then
        log_error "Script not found: ${script_path}"
        exit 1
    fi

    log_section "[${step_number}/${total_steps}] ${step_name}"

    local step_start
    step_start=$(date +%s)

    if bash "${script_path}"; then
        local step_end
        step_end=$(date +%s)
        local step_duration=$((step_end - step_start))
        log_success "${step_name} — done (${step_duration}s)"
        return 0
    else
        log_error "${step_name} — FAILED"
        log_error "Bootstrap aborted at step ${step_number}."
        log_error "Fix the issue and re-run: sudo bash bootstrap/install.sh"
        log_error "Log file: ${LOG_FILE}"
        exit 1
    fi
}

# ==============================================================================
# SUMMARY
# ==============================================================================

print_summary() {
    local duration_min="$1"
    local duration_sec="$2"

    log_section "BOOTSTRAP COMPLETE"

    printf '  Duration:        %dm %ds\n' "${duration_min}" "${duration_sec}"
    printf '\n'

    if [[ "${DRY_RUN}" == "true" ]]; then
        printf '  %sDRY RUN — no changes were made to the system%s\n' "${CYAN}" "${NC}"
        printf '\n'
        return 0
    fi

    # System info
    local docker_ver compose_ver tailscale_ip
    docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "N/A")
    compose_ver=$(docker compose version 2>/dev/null | awk '{print $NF}' || echo "N/A")
    tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "not configured")

    printf '  Docker:          %s\n' "${docker_ver}"
    printf '  Docker Compose:  %s\n' "${compose_ver}"
    printf '  Tailscale IP:    %s\n' "${tailscale_ip}"
    printf '\n'

    printf '  %sNEXT STEPS:%s\n' "${BOLD}" "${NC}"
    if command -v tailscale > /dev/null 2>&1 && [[ "${tailscale_ip}" != "not configured" ]]; then
        printf '  1. SSH via Tailscale: ssh %s@%s\n' "${DEPLOY_USER:-deploy}" "${tailscale_ip}"
    else
        printf '  1. SSH to the server and verify login\n'
    fi
    printf '  2. Verify SSH key login works\n'
    printf '  3. Disable password auth:\n'
    printf '     sudo sed -i '\''s/^PasswordAuthentication yes$/PasswordAuthentication no/'\''\n'
    printf '         /etc/ssh/sshd_config.d/99-mitseri-hardening.conf\n'
    printf '     sudo systemctl reload sshd\n'
    printf '\n'
    printf '  Log: %s\n' "${LOG_FILE}"
    printf '\n'
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    check_root
    trap 'log_error "Bootstrap execution interrupted by user (SIGINT/SIGTERM)"; exit 130' INT TERM

    print_header "Bootstrap Installer" "Production server setup for ${MITSERI_NAME}"

    local start_time
    start_time=$(date +%s)

    # Define steps: "Step Name:script_file.sh"
    local steps=(
        "System Preflight Check:00-preflight.sh"
        "System Update & Essentials:01-system-update.sh"
        "Deploy User Setup:02-user-setup.sh"
        "Docker Engine Installation:03-install-docker.sh"
        "Tailscale Installation:04-install-tailscale.sh"
        "Security Hardening:05-security-hardening.sh"
        "Bootstrap Verification:06-verify.sh"
    )

    local total=${#steps[@]}
    local current=0

    for step in "${steps[@]}"; do
        local name="${step%%:*}"
        local script="${step##*:}"
        current=$((current + 1))
        run_step "${current}" "${total}" "${name}" "${script}"
    done

    # Calculate duration
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    print_summary "${minutes}" "${seconds}"
}

main "$@"
