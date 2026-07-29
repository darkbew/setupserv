#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Review & Pre-Validation Module
# ==============================================================================
#
# Description:
#   Renders the interactive review matrix, section edit menu, and pre-generation
#   validation engine. Prevents `.env` generation if critical validation failures exist.
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

# Validate a specific section and return status string (PASS, WARN, FAIL)
validate_section_status() {
    local target_section="$1"
    local has_fail=false
    local has_warn=false

    local entry var_name section prompt_text desc default_val validator required secret condition
    for entry in "${CONFIG_METADATA[@]}"; do
        IFS='|' read -r var_name section prompt_text desc default_val validator required secret condition <<< "${entry}"
        if [[ "${section}" != "${target_section}" ]]; then
            continue
        fi

        # Check condition
        if [[ -n "${condition}" ]]; then
            local cond_val="${CONFIG_VALUES[${condition}]:-no}"
            if [[ "${cond_val,,}" =~ ^(no|n|false|0)$ ]]; then
                continue
            fi
        fi

        local val="${CONFIG_VALUES[${var_name}]:-}"

        # Check required
        if [[ "${required}" == "true" ]] && [[ -z "${val}" ]]; then
            has_fail=true
            continue
        fi

        # Check placeholder CHANGE_ME
        if [[ "${val}" == "CHANGE_ME" ]] && [[ "${required}" == "true" ]]; then
            if [[ "${secret}" == "secret" ]] || [[ "${var_name}" == *"PASSWORD"* ]]; then
                has_fail=true
            else
                has_warn=true
            fi
            continue
        fi

        # Run validator
        if [[ "${validator}" != "none" ]] && declare -f "${validator}" >/dev/null; then
            if ! "${validator}" "${val}"; then
                has_fail=true
            fi
        fi
    done

    if [[ "${has_fail}" == "true" ]]; then
        echo "FAIL"
    elif [[ "${has_warn}" == "true" ]]; then
        echo "WARN"
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

    printf '  %s1) General           %s : Hostname: %s | Domain: %s | User: %s | SSH Port: %s\n' \
        "$(render_status_badge "${s1}")" "${BOLD}" \
        "${CONFIG_VALUES[HOSTNAME]:-N/A}" \
        "${CONFIG_VALUES[DOMAIN]:-N/A}" \
        "${CONFIG_VALUES[DEPLOY_USER]:-N/A}" \
        "${CONFIG_VALUES[SSH_PORT]:-22}"

    printf '  %s2) Docker            %s : Status: %s | Network: %s | Log Max: %s\n' \
        "$(render_status_badge "${s2}")" "${BOLD}" \
        "${CONFIG_VALUES[INSTALL_DOCKER]:-yes}" \
        "${CONFIG_VALUES[DOCKER_NETWORK_NAME]:-bootstrap-net}" \
        "${CONFIG_VALUES[DOCKER_LOG_MAX_SIZE]:-10m}"

    printf '  %s3) Security          %s : RootLogin: %s | PwdAuth: %s | UFW: %s | Fail2ban: %s\n' \
        "$(render_status_badge "${s3}")" "${BOLD}" \
        "${CONFIG_VALUES[PERMIT_ROOT_LOGIN]:-no}" \
        "${CONFIG_VALUES[SSH_PASSWORD_AUTH]:-yes}" \
        "${CONFIG_VALUES[ENABLE_UFW]:-yes}" \
        "${CONFIG_VALUES[ENABLE_FAIL2BAN]:-yes}"

    printf '  %s4) Tailscale         %s : Status: %s | Hostname: %s\n' \
        "$(render_status_badge "${s4}")" "${BOLD}" \
        "${CONFIG_VALUES[INSTALL_TAILSCALE]:-yes}" \
        "${CONFIG_VALUES[TAILSCALE_HOSTNAME]:-bootstrap-server}"

    printf '  %s5) Monitoring        %s : Status: %s | Grafana: %s | Prometheus: %s\n' \
        "$(render_status_badge "${s5}")" "${BOLD}" \
        "${CONFIG_VALUES[INSTALL_MONITORING]:-no}" \
        "${CONFIG_VALUES[ENABLE_GRAFANA]:-no}" \
        "${CONFIG_VALUES[ENABLE_PROMETHEUS]:-no}"

    printf '  %s6) Backup            %s : Status: %s | Schedule: %s | Target: %s\n' \
        "$(render_status_badge "${s6}")" "${BOLD}" \
        "${CONFIG_VALUES[INSTALL_BACKUP]:-no}" \
        "${CONFIG_VALUES[BACKUP_SCHEDULE]:-N/A}" \
        "${CONFIG_VALUES[BACKUP_REMOTE_NAME]:-gdrive}"

    printf '  %s7) Reverse Proxy     %s : Status: %s (Traefik v3) | User: %s\n' \
        "$(render_status_badge "${s7}")" "${BOLD}" \
        "${CONFIG_VALUES[INSTALL_TRAEFIK]:-yes}" \
        "${CONFIG_VALUES[TRAEFIK_DASHBOARD_USER]:-admin}"

    printf '  %s8) Cloudflare Tunnel %s : Status: %s\n' \
        "$(render_status_badge "${s8}")" "${BOLD}" \
        "${CONFIG_VALUES[INSTALL_CLOUDFLARE_TUNNEL]:-no}"

    printf '%s──────────────────────────────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
}

# Interactively prompt questions for a specific section
prompt_section_interactive() {
    local target_section="$1"
    local section_title="$2"

    log_section "Configuring Section: ${section_title}"

    local entry var_name section prompt_text desc default_val validator required secret condition
    for entry in "${CONFIG_METADATA[@]}"; do
        IFS='|' read -r var_name section prompt_text desc default_val validator required secret condition <<< "${entry}"
        if [[ "${section}" != "${target_section}" ]]; then
            continue
        fi

        # Skip if parent condition is disabled
        if [[ -n "${condition}" ]]; then
            local cond_val="${CONFIG_VALUES[${condition}]:-no}"
            if [[ "${cond_val,,}" =~ ^(no|n|false|0)$ ]]; then
                continue
            fi
        fi

        # Choose appropriate prompt helper based on metadata
        if [[ "${validator}" == "validate_boolean" ]]; then
            prompt_boolean "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
        elif [[ "${secret}" == "secret" ]] || [[ "${var_name}" == *"PASSWORD"* ]]; then
            if [[ "${validator}" == "validate_password" ]]; then
                prompt_password "${var_name}" "${prompt_text}" 12
            else
                prompt_secret "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
            fi
        elif [[ "${validator}" == "validate_port" ]]; then
            prompt_port "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
        elif [[ "${validator}" == "validate_timezone" ]]; then
            prompt_timezone "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
        elif [[ "${validator}" == "validate_positive_integer" ]] || [[ "${validator}" == "validate_integer" ]]; then
            prompt_integer "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
        else
            prompt_text "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}" "${validator}"
        fi
    done
}
