#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Master Installer
# ==============================================================================
#
# Master orchestrator for server bootstrap.
# Runs all bootstrap scripts in sequence or selectively.
# Integrates the Interactive Configuration Wizard subsystem.
#
# Single Entry Point:
#   sudo bash bootstrap/install.sh
#
# Features:
#   - Interactive Configuration Wizard (.env generation)
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
#   sudo bash bootstrap/install.sh --wizard         # Force Configuration Wizard
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
FORCE_WIZARD="false"
SINGLE_STEP=""
START_FROM_STEP=""

# === Parse Arguments ===
usage() {
    printf 'Usage: sudo bash %s [OPTIONS]\n\n' "$0"
    printf 'Options:\n'
    printf '  --wizard, -w         Force launch Interactive Configuration Wizard\n'
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
        --wizard|-w)
            FORCE_WIZARD="true"
            shift
            ;;
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

# Share log file with all child scripts
export LOG_FILE

# ==============================================================================
# CONFIGURATION RESOLUTION
# ==============================================================================

# Resolve .env configuration via wizard or existing file.
# Returns 0 if bootstrap should proceed, exits otherwise.
resolve_configuration() {
    local wizard_script="${BOOTSTRAP_DIR}/config-wizard.sh"
    local need_wizard=false

    # Case 1: --wizard flag was explicitly passed
    if [[ "${FORCE_WIZARD}" == "true" ]]; then
        need_wizard=true
    fi

    # Case 2: .env does not exist — wizard is mandatory
    if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
        log_info "No .env configuration file found"
        need_wizard=true
    fi

    # Case 3: .env exists but wizard was not forced — ask user
    if [[ -f "${PROJECT_ROOT}/.env" ]] && [[ "${FORCE_WIZARD}" != "true" ]] && [[ "${need_wizard}" != "true" ]]; then
        printf '\n'
        printf '  %sExisting configuration detected:%s %s/.env\n' "${BOLD}" "${NC}" "${PROJECT_ROOT}"
        printf '\n'

        local reuse_input=""
        while true; do
            printf '  %sReuse existing configuration?%s [%sY/n%s]: ' "${BOLD}" "${NC}" "${CYAN}" "${NC}"
            read -r reuse_input || reuse_input="yes"
            reuse_input="${reuse_input:-yes}"

            case "${reuse_input,,}" in
                y|yes)
                    log_success "Reusing existing configuration"
                    load_env "${PROJECT_ROOT}/.env"
                    return 0
                    ;;
                n|no)
                    need_wizard=true
                    break
                    ;;
                *)
                    printf '    %s[ERROR]%s Please enter '\''y'\'' or '\''n'\''\n' "${RED}" "${NC}"
                    ;;
            esac
        done
    fi

    # Launch Configuration Wizard
    if [[ "${need_wizard}" == "true" ]]; then
        if [[ ! -f "${wizard_script}" ]]; then
            log_error "Configuration Wizard not found: ${wizard_script}"
            log_error "Cannot generate .env without the wizard. Aborting."
            exit 1
        fi

        local wizard_action_file="${PROJECT_ROOT}/.wizard_action"

        log_info "Launching Interactive Configuration Wizard..."
        if bash "${wizard_script}"; then
            # Read wizard exit action from IPC file
            local wizard_action="EXIT"
            if [[ -f "${wizard_action_file}" ]]; then
                wizard_action=$(cat "${wizard_action_file}")
                rm -f "${wizard_action_file}"
            fi

            if [[ "${wizard_action}" == "EXIT" ]]; then
                log_info "Wizard completed. User chose to exit."
                exit 0
            fi
        else
            rm -f "${wizard_action_file}" 2>/dev/null || true
            log_error "Configuration Wizard failed"
            exit 1
        fi
    fi

    # Load the generated/existing .env
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        load_env "${PROJECT_ROOT}/.env"
    else
        log_error "No .env file available after wizard completion. Aborting."
        exit 1
    fi
}

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
        printf '  1. SSH to the server and login as user '\''%s'\''\n' "${deploy_user}"
    fi
    printf '  2. Masuk ke direktori platform: cd /opt/setupserv\n'
    printf '  3. Verify SSH key login works\n'
    printf '  4. Disable password auth (Phase 2):\n'
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

    # Resolve configuration (.env) via wizard or existing file
    resolve_configuration

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

    # Prompt user whether to deploy Layer 2 Platform Infrastructure
    # After bootstrap, repository has been synced to /opt/setupserv by 02-user-setup.sh
    local platform_root="/opt/setupserv"
    local deploy_script="${platform_root}/scripts/deploy-platform.sh"

    # Fallback: if /opt/setupserv does not exist yet (e.g. --step mode), use original PROJECT_ROOT
    if [[ ! -d "${platform_root}" ]]; then
        platform_root="${PROJECT_ROOT}"
        deploy_script="${PROJECT_ROOT}/scripts/deploy-platform.sh"
    fi

    if [[ -z "${SINGLE_STEP:-}" ]] && [[ -f "${deploy_script}" ]]; then
        printf '\n'
        printf '  %sProceed to deploy Layer 2 Platform Infrastructure (Traefik Proxy & Platform Services)?%s [%sY/n%s]: ' "${BOLD}" "${NC}" "${CYAN}" "${NC}"
        local deploy_input=""
        read -r deploy_input || deploy_input="yes"
        deploy_input="${deploy_input:-yes}"

        case "${deploy_input,,}" in
            y|yes)
                log_section "Launching Layer 2 Platform Infrastructure"
                export PROJECT_ROOT="${platform_root}"
                if bash "${deploy_script}"; then
                    log_success "Layer 2 Platform Infrastructure deployed successfully"
                else
                    log_error "Layer 2 Platform deployment failed"
                    exit 1
                fi
                ;;
            *)
                log_info "Skipping Layer 2 deployment. You can deploy Layer 2 later by running:"
                log_info "  su - ${deploy_user} -c 'cd ${platform_root} && make platform'"
                ;;
        esac
    fi

    # Print final operational instructions
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    printf '\n'
    printf '  %s══════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '  %s  PENTING: LANGKAH SELANJUTNYA                             %s\n' "${BOLD}" "${NC}"
    printf '  %s══════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '\n'
    printf '  Repository telah disalin ke: %s%s%s\n' "${GREEN}" "${platform_root}" "${NC}"
    printf '  Kepemilikan: %s%s:%s%s\n' "${GREEN}" "${deploy_user}" "${deploy_user}" "${NC}"
    printf '\n'
    printf '  Untuk operasional harian, gunakan user %s%s%s:\n' "${CYAN}" "${deploy_user}" "${NC}"
    printf '\n'
    printf '    %ssu - %s%s\n' "${BOLD}" "${deploy_user}" "${NC}"
    printf '    %scd %s%s\n' "${BOLD}" "${platform_root}" "${NC}"
    printf '\n'
    printf '  Semua perintah Docker dapat dijalankan TANPA sudo:\n'
    printf '    make platform        # Deploy Layer 2\n'
    printf '    make verify          # Verifikasi Platform\n'
    printf '    docker compose ps    # Lihat container aktif\n'
    printf '\n'
}

main "$@"
