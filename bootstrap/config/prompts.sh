#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Terminal UI Prompt Helpers & Type Dispatcher
# ==============================================================================
#
# Description:
#   Reusable terminal UI prompt helpers and type-based dispatcher for the
#   configuration subsystem. Handles user input, default value substitution,
#   SHOW_IF/REQUIRED_IF rule evaluation, placeholder checks, and signal safety.
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

# Generic Text Prompt with validation loop, requirement check, and default fallback
prompt_text() {
    local var_name="$1"
    local label="$2"
    local default_val="${3:-}"
    local validator_func="${4:-validate_optional}"
    local required_if_expr="${5:-never}"

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

        # Check REQUIRED_IF rule and placeholder rejection
        if eval_metadata_rule "${required_if_expr}" && is_placeholder "${input_val}"; then
            printf '    %s[ERROR]%s %s is required. Value cannot be empty or placeholder.\n' "${RED}" "${NC}" "${label}"
            continue
        fi

        # Allow empty/placeholder if not required
        if is_placeholder "${input_val}"; then
            CONFIG_VALUES["${var_name}"]=""
            return 0
        fi

        # Validate format
        if [[ "${validator_func}" != "none" ]] && [[ "${validator_func}" != "validate_optional" ]] && declare -f "${validator_func}" >/dev/null; then
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
    local required_if_expr="${4:-never}"

    local current_val="${CONFIG_VALUES[${var_name}]:-${default_val}}"
    local input_val=""

    while true; do
        trap cleanup_terminal_echo EXIT INT TERM
        stty -echo 2>/dev/null || true

        if [[ -n "${current_val}" ]] && [[ "${current_val}" != "CHANGE_ME" ]]; then
            printf '  %s%s%s [%s********%s]: ' "${BOLD}" "${label}" "${NC}" "${CYAN}" "${NC}"
        else
            printf '  %s%s%s: ' "${BOLD}" "${label}" "${NC}"
        fi

        read -r input_val || return 1
        stty echo 2>/dev/null || true
        printf '\n'
        trap - EXIT INT TERM

        input_val="${input_val:-${current_val}}"

        # Check REQUIRED_IF rule and placeholder rejection
        if eval_metadata_rule "${required_if_expr}" && is_placeholder "${input_val}"; then
            printf '    %s[ERROR]%s %s is required. Value cannot be empty or placeholder.\n' "${RED}" "${NC}" "${label}"
            continue
        fi

        if is_placeholder "${input_val}"; then
            CONFIG_VALUES["${var_name}"]=""
            return 0
        fi

        CONFIG_VALUES["${var_name}"]="${input_val}"
        return 0
    done
}

# Password Prompt with strength evaluation, hidden input, confirmation, and weak warning override
prompt_password() {
    local var_name="$1"
    local label="$2"
    local min_len="${3:-12}"
    local required_if_expr="${4:-never}"

    local pass1="" pass2="" strength=""
    while true; do
        # Prompt 1: Password
        trap cleanup_terminal_echo EXIT INT TERM
        stty -echo 2>/dev/null || true
        printf '  %s%s%s (min %d chars): ' "${BOLD}" "${label}" "${NC}" "${min_len}"
        read -r pass1 || return 1
        stty echo 2>/dev/null || true
        printf '\n'

        # Check REQUIRED_IF and placeholder rejection
        if eval_metadata_rule "${required_if_expr}" && is_placeholder "${pass1}"; then
            printf '    %s[ERROR]%s Password is required and cannot be empty or placeholder.\n' "${RED}" "${NC}"
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

# ------------------------------------------------------------------------------
# 2. TYPE DISPATCHER ENGINE
# ------------------------------------------------------------------------------

# Single dispatcher responsible for prompt selection based on metadata TYPE
dispatch_prompt_by_type() {
    local var_name="$1"
    local section="$2"
    local type="$3"
    local prompt_text="$4"
    local description="$5"
    local default_val="$6"
    local validator="$7"
    local show_if="$8"
    local required_if="$9"
    local secret="${10:-false}"

    # Evaluate SHOW_IF visibility rule
    if ! eval_metadata_rule "${show_if}"; then
        return 0
    fi

    case "${type,,}" in
        boolean)
            prompt_boolean "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
            ;;
        password)
            prompt_password "${var_name}" "${prompt_text}" 12 "${required_if}"
            ;;
        secret)
            prompt_secret "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}" "${required_if}"
            ;;
        select)
            prompt_select "${var_name}" "${prompt_text}" "${validator}" "${CONFIG_VALUES[${var_name}]:-${default_val}}"
            ;;
        *)
            prompt_text "${var_name}" "${prompt_text}" "${CONFIG_VALUES[${var_name}]:-${default_val}}" "${validator}" "${required_if}"
            ;;
    esac
}
