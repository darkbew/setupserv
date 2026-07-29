#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Terminal UI Prompt Helpers
# ==============================================================================
#
# Description:
#   Reusable terminal UI prompt helpers for the configuration subsystem.
#   Handles user input, default value substitution, validation loops,
#   password masking, strength warnings, and signal cleanup safety.
#
# Constraints:
#   - Must source validators.sh
#   - Must store selected values in CONFIG_VALUES associative array
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_PROMPTS_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_PROMPTS_SH_LOADED=1

# Ensure validators are loaded
_PROMPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=validators.sh
source "${_PROMPTS_DIR}/validators.sh"

# Ensure global associative array exists
declare -A CONFIG_VALUES 2>/dev/null || true

# Signal cleanup safety helper to ensure terminal echo is restored
cleanup_terminal_echo() {
    stty echo 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 1. CORE PROMPT HELPERS
# ------------------------------------------------------------------------------

# Generic Text Prompt with validation loop and default fallback
prompt_text() {
    local var_name="$1"
    local label="$2"
    local default_val="${3:-}"
    local validator_func="${4:-none}"

    local current_val="${CONFIG_VALUES[${var_name}]:-${default_val}}"
    local input_val=""

    while true; do
        if [[ -n "${current_val}" ]]; then
            printf '  %s%s%s [%s%s%s]: ' "${BOLD}" "${label}" "${NC}" "${CYAN}" "${current_val}" "${NC}"
        else
            printf '  %s%s%s: ' "${BOLD}" "${label}" "${NC}"
        fi

        read -r input_val || return 1
        input_val="${input_val:-${current_val}}"

        # Trim leading/trailing whitespace
        input_val="$(echo "${input_val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # Allow empty if not required and no validator specified
        if [[ -z "${input_val}" ]] && [[ "${validator_func}" == "none" ]]; then
            CONFIG_VALUES["${var_name}"]=""
            return 0
        fi

        # Validate input
        if [[ "${validator_func}" != "none" ]] && declare -f "${validator_func}" >/dev/null; then
            if "${validator_func}" "${input_val}"; then
                CONFIG_VALUES["${var_name}"]="${input_val}"
                return 0
            else
                printf '    %s[ERROR]%s Invalid format for %s. Please try again.\n' "${RED}" "${NC}" "${label}"
            fi
        else
            CONFIG_VALUES["${var_name}"]="${input_val}"
            return 0
        fi
    done
}

# Boolean Prompt (Y/n or y/N)
prompt_boolean() {
    local var_name="$1"
    local label="$2"
    local default_bool="${3:-yes}"

    local default_hint="Y/n"
    if [[ "${default_bool,,}" =~ ^(no|n|false|0)$ ]]; then
        default_hint="y/N"
        default_bool="no"
    else
        default_bool="yes"
    fi

    local input_val=""
    while true; do
        printf '  %s%s%s [%s%s%s]? ' "${BOLD}" "${label}" "${NC}" "${CYAN}" "${default_hint}" "${NC}"
        read -r input_val || return 1
        input_val="${input_val:-${default_bool}}"

        case "${input_val,,}" in
            y|yes|true|1)
                CONFIG_VALUES["${var_name}"]="yes"
                return 0
                ;;
            n|no|false|0)
                CONFIG_VALUES["${var_name}"]="no"
                return 0
                ;;
            *)
                printf '    %s[ERROR]%s Please enter '\''y'\'' or '\''n'\''.\n' "${RED}" "${NC}"
                ;;
        esac
    done
}

# Secret / Hidden Prompt (masking input with read -s)
prompt_secret() {
    local var_name="$1"
    local label="$2"
    local default_val="${3:-}"

    local input_val=""
    while true; do
        trap cleanup_terminal_echo EXIT INT TERM
        stty -echo 2>/dev/null || true
        printf '  %s%s%s: ' "${BOLD}" "${label}" "${NC}"
        read -r input_val || return 1
        stty echo 2>/dev/null || true
        printf '\n'
        trap - EXIT INT TERM

        input_val="${input_val:-${default_val}}"
        if [[ -n "${input_val}" ]]; then
            CONFIG_VALUES["${var_name}"]="${input_val}"
            return 0
        else
            printf '    %s[ERROR]%s Value cannot be empty.\n' "${RED}" "${NC}"
        fi
    done
}

# Password Prompt with strength evaluation, hidden input, confirmation, and weak warning override
prompt_password() {
    local var_name="$1"
    local label="$2"
    local min_len="${3:-12}"

    local pass1="" pass2="" strength=""
    while true; do
        # Prompt 1: Password
        trap cleanup_terminal_echo EXIT INT TERM
        stty -echo 2>/dev/null || true
        printf '  %s%s%s (min %d chars): ' "${BOLD}" "${label}" "${NC}" "${min_len}"
        read -r pass1 || return 1
        stty echo 2>/dev/null || true
        printf '\n'

        if [[ -z "${pass1}" ]]; then
            printf '    %s[ERROR]%s Password cannot be empty.\n' "${RED}" "${NC}"
            trap - EXIT INT TERM
            continue
        fi

        # Evaluate strength
        strength=$(evaluate_password_strength "${pass1}")

        if [[ "${strength}" == "WEAK" ]]; then
            printf '    %s[WARN]%s Password strength is WEAK (length %d, recommended 12+ with mixed characters).\n' "${YELLOW}" "${NC}" "${#pass1}"
            stty echo 2>/dev/null || true
            trap - EXIT INT TERM
            if ! prompt_confirm "Accept weak password and proceed anyway" "no"; then
                continue
            fi
        else
            printf '    %s[OK]%s Password strength: %s\n' "${GREEN}" "${NC}" "${strength}"
        fi

        # Prompt 2: Confirm password
        trap cleanup_terminal_echo EXIT INT TERM
        stty -echo 2>/dev/null || true
        printf '  %sConfirm %s%s: ' "${BOLD}" "${label}" "${NC}"
        read -r pass2 || return 1
        stty echo 2>/dev/null || true
        printf '\n'
        trap - EXIT INT TERM

        if [[ "${pass1}" != "${pass2}" ]]; then
            printf '    %s[ERROR]%s Passwords do not match. Please try again.\n' "${RED}" "${NC}"
            continue
        fi

        CONFIG_VALUES["${var_name}"]="${pass1}"
        return 0
    done
}

# Port Number Prompt Helper
prompt_port() {
    local var_name="$1"
    local label="$2"
    local default_port="${3:-22}"

    prompt_text "${var_name}" "${label}" "${default_port}" "validate_port"
}

# Timezone Prompt Helper
prompt_timezone() {
    local var_name="$1"
    local label="$2"
    local default_tz="${3:-Asia/Jakarta}"

    prompt_text "${var_name}" "${label}" "${default_tz}" "validate_timezone"
}

# Integer Prompt Helper
prompt_integer() {
    local var_name="$1"
    local label="$2"
    local default_int="${3:-1}"

    prompt_text "${var_name}" "${label}" "${default_int}" "validate_integer"
}

# Selection Menu Prompt
prompt_select() {
    local var_name="$1"
    local label="$2"
    local options_ref="$3" # Name of array variable
    local default_val="${4:-1}"

    local -n options="${options_ref}"

    printf '\n  %s%s%s:\n' "${BOLD}" "${label}" "${NC}"
    local i=1
    for opt in "${options[@]}"; do
        printf '    %s%d)%s %s\n' "${CYAN}" "${i}" "${NC}" "${opt}"
        i=$((i + 1))
    done

    local choice=""
    while true; do
        printf '  %sSelect option%s [%s%s%s]: ' "${BOLD}" "${NC}" "${CYAN}" "${default_val}" "${NC}"
        read -r choice || return 1
        choice="${choice:-${default_val}}"

        if [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#options[@]}" ]]; then
            local selected_idx=$((choice - 1))
            CONFIG_VALUES["${var_name}"]="${options[${selected_idx}]}"
            return 0
        else
            printf '    %s[ERROR]%s Invalid selection. Choose between 1 and %d.\n' "${RED}" "${NC}" "${#options[@]}"
        fi
    done
}

# Confirmation Prompt (Returns 0 for Yes, 1 for No)
prompt_confirm() {
    local label="$1"
    local default_bool="${2:-yes}"

    local default_hint="Y/n"
    if [[ "${default_bool,,}" =~ ^(no|n|false|0)$ ]]; then
        default_hint="y/N"
        default_bool="no"
    else
        default_bool="yes"
    fi

    local input_val=""
    while true; do
        printf '  %s%s%s [%s%s%s]? ' "${BOLD}" "${label}" "${NC}" "${CYAN}" "${default_hint}" "${NC}"
        read -r input_val || return 1
        input_val="${input_val:-${default_bool}}"

        case "${input_val,,}" in
            y|yes|true|1) return 0 ;;
            n|no|false|0) return 1 ;;
            *) printf '    %s[ERROR]%s Please enter '\''y'\'' or '\''n'\''.\n' "${RED}" "${NC}" ;;
        esac
    done
}
