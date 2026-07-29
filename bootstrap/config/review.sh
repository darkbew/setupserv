#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Review & Pre-Validation Module
# ==============================================================================
#
# Description:
#   Renders the interactive review matrix, section edit menu, and pre-generation
#   validation engine. Uses eval_metadata_rule and is_placeholder.
#   Prevents `.env` generation if critical validation failures exist.
#
# Constraints:
#   - Must source wizard-metadata.sh and prompts.sh
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_REVIEW_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_REVIEW_SH_LOADED=1

_REVIEW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=wizard-metadata.sh
source "${_REVIEW_DIR}/wizard-metadata.sh"
# shellcheck source=prompts.sh
source "${_REVIEW_DIR}/prompts.sh"

# Ensure global associative array exists
declare -A CONFIG_VALUES 2>/dev/null || true

# Collect array of missing required variable prompt titles for a section
get_section_missing_vars() {
    local target_section="$1"
    local missing_list=()

    local entry var_name section type prompt_text desc default_val validator show_if required_if secret
    for entry in "${CONFIG_METADATA[@]}"; do
        IFS='|' read -r var_name section type prompt_text desc default_val validator show_if required_if secret <<< "${entry}"
        if [[ "${section}" != "${target_section}" ]]; then
            continue
        fi

        # Skip if REQUIRED_IF rule is not active
        if ! eval_metadata_rule "${required_if}"; then
            continue
        fi

        local val="${CONFIG_VALUES[${var_name}]:-}"

        # If required rule is active and value is placeholder / empty, mark missing
        if is_placeholder "${val}"; then
            missing_list+=("${prompt_text}")
            continue
        fi

        # Format validation check
        if [[ "${validator}" != "none" ]] && [[ "${validator}" != "validate_optional" ]] && declare -f "${validator}" >/dev/null; then
            if ! "${validator}" "${val}"; then
                missing_list+=("${prompt_text} (Invalid format)")
            fi
        fi
    done

    if [[ ${#missing_list[@]} -gt 0 ]]; then
        printf '%s\n' "${missing_list[@]}"
    fi
}

# Validate a specific section and return status string (PASS, WARN, FAIL)
validate_section_status() {
    local target_section="$1"
    local missing
    missing=$(get_section_missing_vars "${target_section}")

    if [[ -n "${missing}" ]]; then
        echo "FAIL"
    else
        echo "PASS"
    fi
}

# Render section status badge with ANSI colors
render_status_badge() {
    local status="$1"
    case "${status}" in
        PASS) printf '%s[PASS]%s' "${GREEN}" "${NC}" ;;
        WARN) printf '%s[WARN]%s' "${YELLOW}" "${NC}" ;;
        FAIL) printf '%s[FAIL]%s' "${RED}" "${NC}" ;;
        *)    printf '%s[SKIP]%s' "${CYAN}" "${NC}" ;;
    esac
}

# Helper to render bulleted list of missing required fields if section failed
render_section_missing_bullets() {
    local section_id="$1"
    local missing_raw
    missing_raw=$(get_section_missing_vars "${section_id}")

    if [[ -n "${missing_raw}" ]]; then
        printf '         %s↳ Missing required fields:%s\n' "${RED}" "${NC}"
        local item
        while IFS= read -r item; do
            [[ -z "${item}" ]] && continue
            printf '           %s•%s %s\n' "${RED}" "${NC}" "${item}"
        done <<< "${missing_raw}"
    fi
}

# Display full review matrix
render_review_matrix() {
    printf '\n'
    printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '%s  CONFIGURATION SUBSYSTEM — REVIEW MATRIX & VALIDATION                        %s\n' "${BOLD}" "${NC}"
    printf '%s══════════════════════════════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '\n'

    local s1 s2 s3 s4 s5 s6 s7 s8
    s1=$(validate_section_status "1_general")
    s2=$(validate_section_status "2_docker")
    s3=$(validate_section_status "3_security")
    s4=$(validate_section_status "4_tailscale")
    s5=$(validate_section_status "5_monitoring")
    s6=$(validate_section_status "6_backup")
    s7=$(validate_section_status "7_traefik")
    s8=$(validate_section_status "8_cloudflare")

    printf '  %s 1) General           : Hostname: %s | Domain: %s | User: %s | SSH Port: %s\n' \
        "$(render_status_badge "${s1}")" \
        "${CONFIG_VALUES[HOSTNAME]:-N/A}" \
        "${CONFIG_VALUES[DOMAIN]:-N/A}" \
        "${CONFIG_VALUES[DEPLOY_USER]:-N/A}" \
        "${CONFIG_VALUES[SSH_PORT]:-22}"
    render_section_missing_bullets "1_general"

    printf '  %s 2) Docker            : Status: %s | Network: %s | Log Max: %s\n' \
        "$(render_status_badge "${s2}")" \
        "${CONFIG_VALUES[INSTALL_DOCKER]:-yes}" \
        "${CONFIG_VALUES[DOCKER_NETWORK_NAME]:-bootstrap-net}" \
        "${CONFIG_VALUES[DOCKER_LOG_MAX_SIZE]:-10m}"
    render_section_missing_bullets "2_docker"

    printf '  %s 3) Security          : RootLogin: %s | PwdAuth: %s | UFW: %s | Fail2ban: %s\n' \
        "$(render_status_badge "${s3}")" \
        "${CONFIG_VALUES[PERMIT_ROOT_LOGIN]:-no}" \
        "${CONFIG_VALUES[SSH_PASSWORD_AUTH]:-yes}" \
        "${CONFIG_VALUES[ENABLE_UFW]:-yes}" \
        "${CONFIG_VALUES[ENABLE_FAIL2BAN]:-yes}"
    render_section_missing_bullets "3_security"

    printf '  %s 4) Tailscale         : Status: %s | Hostname: %s\n' \
        "$(render_status_badge "${s4}")" \
        "${CONFIG_VALUES[INSTALL_TAILSCALE]:-yes}" \
        "${CONFIG_VALUES[TAILSCALE_HOSTNAME]:-bootstrap-server}"
    render_section_missing_bullets "4_tailscale"

    printf '  %s 5) Monitoring        : Status: %s | Grafana: %s | Prometheus: %s\n' \
        "$(render_status_badge "${s5}")" \
        "${CONFIG_VALUES[INSTALL_MONITORING]:-no}" \
        "${CONFIG_VALUES[ENABLE_GRAFANA]:-no}" \
        "${CONFIG_VALUES[ENABLE_PROMETHEUS]:-no}"
    render_section_missing_bullets "5_monitoring"

    printf '  %s 6) Backup            : Status: %s | Schedule: %s | Target: %s\n' \
        "$(render_status_badge "${s6}")" \
        "${CONFIG_VALUES[INSTALL_BACKUP]:-no}" \
        "${CONFIG_VALUES[BACKUP_SCHEDULE]:-N/A}" \
        "${CONFIG_VALUES[BACKUP_REMOTE_NAME]:-gdrive}"
    render_section_missing_bullets "6_backup"

    printf '  %s 7) Reverse Proxy     : Status: %s (Traefik v3) | User: %s\n' \
        "$(render_status_badge "${s7}")" \
        "${CONFIG_VALUES[INSTALL_TRAEFIK]:-yes}" \
        "${CONFIG_VALUES[TRAEFIK_DASHBOARD_USER]:-admin}"
    render_section_missing_bullets "7_traefik"

    printf '  %s 8) Cloudflare Tunnel : Status: %s\n' \
        "$(render_status_badge "${s8}")" \
        "${CONFIG_VALUES[INSTALL_CLOUDFLARE_TUNNEL]:-no}"
    render_section_missing_bullets "8_cloudflare"

    printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
}

# Interactively prompt questions for a specific section using type dispatcher
prompt_section_interactive() {
    local target_section="$1"
    local section_title="$2"

    log_section "Configuring Section: ${section_title}"

    local entry var_name section type prompt_text desc default_val validator show_if required_if secret
    for entry in "${CONFIG_METADATA[@]}"; do
        IFS='|' read -r var_name section type prompt_text desc default_val validator show_if required_if secret <<< "${entry}"
        if [[ "${section}" != "${target_section}" ]]; then
            continue
        fi

        dispatch_prompt_by_type "${var_name}" "${section}" "${type}" "${prompt_text}" "${desc}" "${default_val}" "${validator}" "${show_if}" "${required_if}" "${secret}"
    done
}
