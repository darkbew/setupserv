#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Interactive Configuration Wizard
# ==============================================================================
#
# Master orchestrator for the interactive configuration subsystem.
# Prompts user for infrastructure settings, validates input, handles deployment
# presets, renders an interactive review matrix, and generates a formatted .env file.
#
# Usage:
#   sudo bash bootstrap/config-wizard.sh
#
# System Requirements:
#   Ubuntu Server 22.04 / 24.04 LTS — Bash 5.2+
#
# ==============================================================================

# === Resolve Script Location ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# === Source Common Library ===
# shellcheck source=lib/common.sh
source "${BOOTSTRAP_DIR}/lib/common.sh"

# === Source Configuration Subsystem Modules ===
CONFIG_SUB_DIR="${BOOTSTRAP_DIR}/config"

# shellcheck source=config/validators.sh
source "${CONFIG_SUB_DIR}/validators.sh"
# shellcheck source=config/prompts.sh
source "${CONFIG_SUB_DIR}/prompts.sh"
# shellcheck source=config/presets.sh
source "${CONFIG_SUB_DIR}/presets.sh"
# shellcheck source=config/wizard-metadata.sh
source "${CONFIG_SUB_DIR}/wizard-metadata.sh"
# shellcheck source=config/review.sh
source "${CONFIG_SUB_DIR}/review.sh"
# shellcheck source=config/generator.sh
source "${CONFIG_SUB_DIR}/generator.sh"
# shellcheck source=config/loader.sh
source "${CONFIG_SUB_DIR}/loader.sh"

# File-based IPC for wizard action (child process cannot export to parent)
# The wizard writes its final action to this file; install.sh reads it.
WIZARD_ACTION_FILE="${PROJECT_ROOT}/.wizard_action"

# Signal cleanup handler for graceful termination
cleanup_wizard_terminal() {
    stty echo 2>/dev/null || true
    # Write EXIT action so install.sh knows wizard was interrupted
    printf 'EXIT' > "${WIZARD_ACTION_FILE}" 2>/dev/null || true
    printf '\n\n%s[WARN] Configuration Wizard interrupted by user (SIGINT/SIGTERM)%s\n' "${YELLOW}" "${NC}"
    exit 130
}

# ------------------------------------------------------------------------------
# PRESET SELECTION MENU
# ------------------------------------------------------------------------------

select_preset_menu() {
    log_section "Deployment Profile Preset"
    printf '  Select a deployment profile preset to pre-populate configuration defaults:\n\n'
    printf '    %s1)%s Development   (Minimal stack: Docker, Security baseline)\n' "${CYAN}" "${NC}"
    printf '    %s2)%s Staging       (Balanced testing: Docker, Security, Tailscale, Monitoring)\n' "${CYAN}" "${NC}"
    printf '    %s3)%s Production    (Full enterprise: Docker, Security, Tailscale, Monitoring, Backup, Traefik)\n' "${CYAN}" "${NC}"
    printf '    %s4)%s Custom        (Configure every setting step-by-step)\n' "${CYAN}" "${NC}"
    printf '\n'

    local choice=""
    while true; do
        printf '  %sSelect preset%s [%s3%s]: ' "${BOLD}" "${NC}" "${CYAN}" "${NC}"
        read -r choice || return 1
        choice="${choice:-3}"

        case "${choice}" in
            1) apply_preset_development; break ;;
            2) apply_preset_staging; break ;;
            3) apply_preset_production; break ;;
            4) apply_preset_custom; break ;;
            *) printf '    %s[ERROR]%s Invalid option. Choose 1, 2, 3, or 4.\n' "${RED}" "${NC}" ;;
        esac
    done

    log_success "Applied preset: ${CONFIG_VALUES[PRESET_NAME]:-Custom}"
}

# ------------------------------------------------------------------------------
# INTERACTIVE SECTION WIZARD LOOP
# ------------------------------------------------------------------------------

run_full_interactive_wizard() {
    prompt_section_interactive "1_general" "General Settings"
    prompt_section_interactive "2_docker" "Docker Engine Runtime"
    prompt_section_interactive "3_security" "Security Hardening Baseline"
    prompt_section_interactive "4_tailscale" "Tailscale Mesh VPN"
    prompt_section_interactive "5_monitoring" "Prometheus & Grafana Monitoring"
    prompt_section_interactive "6_backup" "Automated Rclone Backup"
    prompt_section_interactive "7_traefik" "Traefik Reverse Proxy"
    prompt_section_interactive "8_cloudflare" "Cloudflare Zero Trust Tunnel"
}

# ------------------------------------------------------------------------------
# REVIEW & GENERATION MENU LOOP
# ------------------------------------------------------------------------------

review_and_generate_loop() {
    while true; do
        render_review_matrix

        printf '\n  %sACTIONS:%s\n' "${BOLD}" "${NC}"
        printf '    %s1-8)%s Edit specific section\n' "${CYAN}" "${NC}"
        printf '    %sG)%s   Generate Configuration & Continue\n' "${GREEN}" "${NC}"
        printf '    %sQ)%s   Quit Wizard\n' "${RED}" "${NC}"
        printf '\n'

        local choice=""
        printf '  %sSelect option%s [%sG%s]: ' "${BOLD}" "${NC}" "${GREEN}" "${NC}"
        read -r choice || return 1
        choice="${choice:-G}"

        case "${choice,,}" in
            1) prompt_section_interactive "1_general" "General Settings" ;;
            2) prompt_section_interactive "2_docker" "Docker Engine Runtime" ;;
            3) prompt_section_interactive "3_security" "Security Hardening Baseline" ;;
            4) prompt_section_interactive "4_tailscale" "Tailscale Mesh VPN" ;;
            5) prompt_section_interactive "5_monitoring" "Prometheus & Grafana Monitoring" ;;
            6) prompt_section_interactive "6_backup" "Automated Rclone Backup" ;;
            7) prompt_section_interactive "7_traefik" "Traefik Reverse Proxy" ;;
            8) prompt_section_interactive "8_cloudflare" "Cloudflare Zero Trust Tunnel" ;;
            g|generate)
                log_info "Validating configuration before generation..."
                local has_fail=false
                local sec
                for sec in "1_general" "2_docker" "3_security" "4_tailscale" "5_monitoring" "6_backup" "7_traefik" "8_cloudflare"; do
                    if [[ "$(validate_section_status "${sec}")" == "FAIL" ]]; then
                        has_fail=true
                        break
                    fi
                done

                if [[ "${has_fail}" == "true" ]]; then
                    printf '\n    %s[ERROR]%s Critical validation failures found in one or more sections.\n' "${RED}" "${NC}"
                    printf '    Please edit sections marked %s[FAIL]%s before generating.\n\n' "${RED}" "${NC}"
                    continue
                fi

                generate_env_file "${PROJECT_ROOT}"
                return 0
                ;;
            q|quit)
                log_info "Wizard exit requested by user"
                printf 'EXIT' > "${WIZARD_ACTION_FILE}" 2>/dev/null || true
                return 0
                ;;
            *)
                printf '    %s[ERROR]%s Invalid selection. Choose 1-8, G, or Q.\n' "${RED}" "${NC}"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# POST GENERATION NAVIGATION MENU
# ------------------------------------------------------------------------------

post_generation_menu() {
    printf '\n'
    printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '%s  CONFIGURATION GENERATED SUCCESSFULLY                                      %s\n' "${BOLD}" "${NC}"
    printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '  Location   : %s/.env\n' "${PROJECT_ROOT}"
    printf '  Validation : %sPASS%s\n' "${GREEN}" "${NC}"
    printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
    printf '\n'
    printf '  %sChoose next action:%s\n' "${BOLD}" "${NC}"
    printf '    %s1)%s Install Server Now (Proceed with Bootstrap steps 00–06)\n' "${GREEN}" "${NC}"
    printf '    %s2)%s Open .env in text editor (%s)\n' "${CYAN}" "${NC}" "${EDITOR:-nano}"
    printf '    %s3)%s Exit Wizard\n' "${YELLOW}" "${NC}"
    printf '\n'

    local choice=""
    while true; do
        printf '  %sSelect action%s [%s1%s]: ' "${BOLD}" "${NC}" "${GREEN}" "${NC}"
        read -r choice || return 1
        choice="${choice:-1}"

        case "${choice}" in
            1)
                printf 'INSTALL' > "${WIZARD_ACTION_FILE}"
                log_success "Proceeding to server bootstrap installation..."
                return 0
                ;;
            2)
                local ed="${EDITOR:-nano}"
                log_info "Opening ${PROJECT_ROOT}/.env with ${ed}..."
                "${ed}" "${PROJECT_ROOT}/.env" || true
                post_generation_menu
                return 0
                ;;
            3)
                printf 'EXIT' > "${WIZARD_ACTION_FILE}"
                log_info "Exiting Configuration Wizard."
                return 0
                ;;
            *)
                printf '    %s[ERROR]%s Invalid option. Choose 1, 2, or 3.\n' "${RED}" "${NC}"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# MAIN WIZARD ORCHESTRATION
# ------------------------------------------------------------------------------

main() {
    check_root
    trap cleanup_wizard_terminal INT TERM

    print_header "Configuration Wizard" "Interactive server setup and .env builder"

    # Pre-load existing .env into memory if present
    if has_env_file "${PROJECT_ROOT}"; then
        load_subsystem_config "${PROJECT_ROOT}" || true
    fi

    # Step 1: Select Preset Profile
    select_preset_menu

    # Step 2: Run interactive prompts if Custom or user editing
    if [[ "${CONFIG_VALUES[PRESET_NAME]:-}" == "Custom" ]]; then
        run_full_interactive_wizard
    fi

    # Step 3: Interactive Review Matrix & Section Editor
    review_and_generate_loop

    # Step 4: Post Generation Action Menu (if .env was generated)
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        post_generation_menu
    else
        # No .env generated (user quit during review)
        printf 'EXIT' > "${WIZARD_ACTION_FILE}" 2>/dev/null || true
    fi
}

main "$@"
