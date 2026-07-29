#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Loader Subsystem
# ==============================================================================
#
# Description:
#   Handles .env file existence checks, environment variable loading via load_env(),
#   configuration defaults initialization, and migration compatibility.
#   Contains NO terminal prompt logic.
#
# Constraints:
#   - Must use load_env() from lib/common.sh
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_LOADER_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_LOADER_SH_LOADED=1

# Ensure global associative array exists
declare -A CONFIG_VALUES 2>/dev/null || true

# Check if .env configuration file exists
has_env_file() {
    local project_root="${1:-.}"
    if [[ -f "${project_root}/.env" ]]; then
        return 0
    else
        return 1
    fi
}

# Load environment configuration from .env into memory and CONFIG_VALUES array
load_subsystem_config() {
    local project_root="${1:-.}"
    local env_path="${project_root}/.env"

    if ! has_env_file "${project_root}"; then
        log_warn "Configuration file not found: ${env_path}"
        return 1
    fi

    # Load environment variables into shell environment
    load_env "${env_path}"

    # Sync environment variables into CONFIG_VALUES array for wizard inspection
    local line key val
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *"="* ]] && continue

        key="${line%%=*}"
        val="${line#*=}"
        key="${key// /}"

        # Strip quotes
        val="${val#\"}"
        val="${val%\"}"
        val="${val#\'}"
        val="${val%\'}"

        if [[ -n "${key}" ]]; then
            CONFIG_VALUES["${key}"]="${val}"
        fi
    done < "${env_path}"

    log_success "Subsystem configuration loaded successfully"
    return 0
}
