#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Validators Module
# ==============================================================================
#
# Description:
#   Pure validation functions for the configuration subsystem.
#   Functions accept input strings as arguments and return 0 (valid) or 1 (invalid).
#   Contains NO terminal prompt logic or UI elements.
#
# Constraints:
#   - Must be sourced by config-wizard.sh
#   - Must adhere to set -Eeuo pipefail
#   - Must use local variables for internal state
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_VALIDATORS_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_VALIDATORS_SH_LOADED=1

# ------------------------------------------------------------------------------
# 1. NETWORK & NAMING VALIDATORS
# ------------------------------------------------------------------------------

# Hostname format validator (RFC 1123 compliant)
validate_hostname() {
    local host_str="${1:-}"
    if [[ "${host_str}" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}$ ]]; then
        return 0
    fi
    return 1
}

# Subdomain format validator
validate_subdomain() {
    local sub_str="${1:-}"
    if [[ "${sub_str}" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}$ ]]; then
        return 0
    fi
    return 1
}

# FQDN Domain format validator
validate_domain() {
    local domain_str="${1:-}"
    if [[ "${domain_str}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        return 0
    fi
    return 1
}

# Linux username validator (rejects root)
validate_username() {
    local user_str="${1:-}"
    if [[ "${user_str}" == "root" ]]; then
        return 1
    fi
    if [[ "${user_str}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi
    return 1
}

# Timezone format validator (IANA format or zoneinfo check)
validate_timezone() {
    local tz_str="${1:-}"
    if [[ -z "${tz_str}" ]]; then
        return 1
    fi
    if [[ -f "/usr/share/zoneinfo/${tz_str}" ]]; then
        return 0
    fi
    if [[ "${tz_str}" =~ ^[A-Za-z_]+/[A-Za-z_]+$ ]]; then
        return 0
    fi
    return 1
}

# IP address or CIDR validator
validate_cidr() {
    local cidr_str="${1:-}"
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'
    if [[ "${cidr_str}" =~ ${rx} ]]; then
        return 0
    fi
    return 1
}

# URL format validator
validate_url() {
    local url_str="${1:-}"
    if [[ "${url_str}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        return 0
    fi
    return 1
}

# Email address format validator
validate_email() {
    local email_str="${1:-}"
    if [[ "${email_str}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# 2. NUMERIC & PORT VALIDATORS
# ------------------------------------------------------------------------------

# Port number validator (1-65535)
validate_port() {
    local port_str="${1:-}"
    if [[ "${port_str}" =~ ^[0-9]+$ ]] && [[ "${port_str}" -ge 1 ]] && [[ "${port_str}" -le 65535 ]]; then
        return 0
    fi
    return 1
}

# General integer validator
validate_integer() {
    local int_str="${1:-}"
    if [[ "${int_str}" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

# Positive integer validator (> 0)
validate_positive_integer() {
    local int_str="${1:-}"
    if [[ "${int_str}" =~ ^[0-9]+$ ]] && [[ "${int_str}" -gt 0 ]]; then
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# 3. CRON & DOCKER VALIDATORS
# ------------------------------------------------------------------------------

# Standard 5-field cron syntax validator
validate_cron() {
    local cron_str="${1:-}"
    if [[ "${cron_str}" =~ ^([0-9*,/-]+\ +){4}[0-9*,/-]+$ ]]; then
        return 0
    fi
    return 1
}

# Docker log max-size validator (e.g. 10m, 100k, 1g)
validate_docker_log_size() {
    local size_str="${1:-}"
    if [[ "${size_str}" =~ ^[0-9]+[kKmMgG]$ ]]; then
        return 0
    fi
    return 1
}

# Docker container restart policy validator
validate_docker_restart() {
    local policy_str="${1:-}"
    case "${policy_str}" in
        always|unless-stopped|on-failure|no) return 0 ;;
        *) return 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# 4. BOOLEAN & PASSWORD VALIDATORS
# ------------------------------------------------------------------------------

# Boolean string validator (yes/no, y/n, true/false, 1/0)
validate_boolean() {
    local bool_str="${1:-}"
    case "${bool_str,,}" in
        yes|y|true|1|no|n|false|0) return 0 ;;
        *) return 1 ;;
    esac
}

# Evaluate password strength
# Outputs: "WEAK", "MEDIUM", or "STRONG"
evaluate_password_strength() {
    local pwd_str="${1:-}"
    local len=${#pwd_str}

    if [[ "${len}" -lt 12 ]]; then
        echo "WEAK"
        return 0
    fi

    local score=0
    [[ "${pwd_str}" =~ [a-z] ]] && score=$((score + 1))
    [[ "${pwd_str}" =~ [A-Z] ]] && score=$((score + 1))
    [[ "${pwd_str}" =~ [0-9] ]] && score=$((score + 1))
    [[ "${pwd_str}" =~ [^a-zA-Z0-9] ]] && score=$((score + 1))

    if [[ "${score}" -ge 4 ]] && [[ "${len}" -ge 16 ]]; then
        echo "STRONG"
    elif [[ "${score}" -ge 2 ]] && [[ "${len}" -ge 12 ]]; then
        echo "MEDIUM"
    else
        echo "WEAK"
    fi
}

# Password validator: returns 0 if length >= 12, returns 1 if less or empty
validate_password() {
    local pwd_str="${1:-}"
    if [[ -n "${pwd_str}" ]] && [[ "${#pwd_str}" -ge 12 ]]; then
        return 0
    fi
    return 1
}
