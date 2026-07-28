#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Master Installer
# ==============================================================================
#
# Master orchestrator for server bootstrap.
# Runs all bootstrap scripts in sequence or selectively.
#
# Single Entry Point:
#   sudo bash bootstrap/install.sh
#
# Features:
#   - Runs all bootstrap steps (00–06) in sequence
#   - Supports selective execution (--step N)
#   - Supports resume / start from step (--start-from N)
#   - Stops immediately on any failure
#   - Supports --dry-run mode (or DRY_RUN=true)
#   - Logs everything to /var/log/bootstrap-framework/
#   - Fully idempotent — safe to re-run
#   - Prints summary with next steps
#
# Usage:
#   sudo bash bootstrap/install.sh                  # Full production run
#   sudo bash bootstrap/install.sh --dry-run        # Simulate full run
#   sudo bash bootstrap/install.sh --step 03        # Execute step 03 only
#   sudo bash bootstrap/install.sh --start-from 03  # Resume from step 03
#
# ==============================================================================

# === Resolve Script Location ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# === Default Runtime Flags ===
DRY_RUN="${DRY_RUN:-false}"
SINGLE_STEP=""
START_FROM_STEP=""

# === Parse Arguments ===
usage() {
    printf 'Usage: sudo bash %s [OPTIONS]\n\n' "$0"
    printf 'Options:\n'
    printf '  --dry-run, -d        Simulate without making changes\n'
    printf '  --step, -s STEP      Run specific step only (e.g., 00, 03, 06)\n'
    printf '  --start-from, -r STEP Resume or start from specific step (e.g., 03)\n'
    printf '  --help, -h           Show this help message\n'
    printf '\n'
    printf 'Environment:\n'
    printf '  DRY_RUN=true         Same as --dry-run\n'
    printf '  LOG_DIR=path         Override log directory\n'
    printf '\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-d)
            DRY_RUN="true"
            shift
            ;;
        --step|-s)
            SINGLE_STEP="$2"
            shift 2
            ;;
        --start-from|-r|--resume)
            START_FROM_STEP="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage
            exit 1
            ;;
    esac
done

export DRY_RUN
export PROJECT_ROOT
export LOG_DIR="${LOG_DIR:-/var/log/bootstrap-framework}"

# === Source Common Library ===
# shellcheck source=lib/common.sh
source "${BOOTSTRAP_DIR}/lib/common.sh"

# === Load Environment ===
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    load_env "${PROJECT_ROOT}/.env"
fi

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
        log_error "Fix the issue and re-run: sudo bash bootstrap/install.sh --start-from ${step_file_code:-${script_file:0:2}}"
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
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"

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

    printf '  Docker Engine:   %s\n' "${docker_ver}"
    printf '  Docker Compose:  %s\n' "${compose_ver}"
    printf '  Tailscale IP:    %s\n' "${tailscale_ip}"
    printf '\n'

    printf '  %sNEXT STEPS:%s\n' "${BOLD}" "${NC}"
    if command -v tailscale > /dev/null 2>&1 && [[ "${tailscale_ip}" != "not configured" ]]; then
        printf '  1. SSH via Tailscale: ssh %s@%s\n' "${deploy_user}" "${tailscale_ip}"
    else
        printf '  1. SSH to the server and verify login as user '\''%s'\''\n' "${deploy_user}"
    fi
    printf '  2. Verify SSH key login works\n'
    printf '  3. Disable password auth (Phase 2):\n'
    printf '     sudo sed -i '\''s/^PasswordAuthentication yes$/PasswordAuthentication no/'\'' \\\n'
    printf '         /etc/ssh/sshd_config.d/99-bootstrap-hardening.conf\n'
    printf '     sudo systemctl reload ssh\n'
    printf '\n'
    printf '  Log File: %s\n' "${LOG_FILE}"
    printf '\n'
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

main() {
    check_root
    trap 'log_error "Bootstrap execution interrupted by user (SIGINT/SIGTERM)"; exit 130' INT TERM

    print_header "Bootstrap Installer" "Production server setup orchestrator"

    local start_time
    start_time=$(date +%s)

    # Define steps: "code:Step Name:script_file.sh"
    local steps=(
        "00:System Preflight Check:00-preflight.sh"
        "01:System Update & Essentials:01-system-update.sh"
        "02:Deploy User Setup:02-user-setup.sh"
        "03:Docker Engine Installation:03-install-docker.sh"
        "04:Tailscale Installation:04-install-tailscale.sh"
        "05:Security Hardening:05-security-hardening.sh"
        "06:Bootstrap Verification:06-verify.sh"
    )

    local total=${#steps[@]}
    local current=0
    local should_run=true

    if [[ -n "${START_FROM_STEP}" ]]; then
        should_run=false
        log_info "Selective Mode: Starting execution from step ${START_FROM_STEP}"
    fi

    if [[ -n "${SINGLE_STEP}" ]]; then
        log_info "Selective Mode: Executing step ${SINGLE_STEP} only"
    fi

    for step in "${steps[@]}"; do
        local code="${step%%:*}"
        local rest="${step#*:}"
        local name="${rest%%:*}"
        local script="${rest##*:}"
        current=$((current + 1))

        # Check start-from threshold
        if [[ -n "${START_FROM_STEP}" ]] && [[ "${code}" == "${START_FROM_STEP}" ]]; then
            should_run=true
        fi

        # Filter for single step execution
        if [[ -n "${SINGLE_STEP}" ]]; then
            if [[ "${code}" == "${SINGLE_STEP}" ]]; then
                step_file_code="${code}"
                run_step "${current}" "${total}" "${name}" "${script}"
            fi
            continue
        fi

        if [[ "${should_run}" == "true" ]]; then
            step_file_code="${code}"
            run_step "${current}" "${total}" "${name}" "${script}"
        fi
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
