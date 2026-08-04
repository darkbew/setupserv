#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — .env Generator & Backup Engine
# ==============================================================================
#
# Description:
#   Validates all REQUIRED_IF metadata rules via eval_metadata_rule and is_placeholder,
#   parses .env.example line-by-line while preserving comments/formatting, and writes
#   the target .env with timestamped backup support.
#
# Constraints:
#   - Must use write_config() and backup_config() from lib/common.sh
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_GENERATOR_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_GENERATOR_SH_LOADED=1

# Ensure global associative array exists
declare -A CONFIG_VALUES 2>/dev/null || true

# Validate generator requirement rules before writing .env
validate_generator_requirements() {
    local failed=0
    local entry var_name section type prompt_text desc default_val validator show_if required_if secret

    for entry in "${CONFIG_METADATA[@]}"; do
        IFS='|' read -r var_name section type prompt_text desc default_val validator show_if required_if secret <<< "${entry}"

        # Evaluate REQUIRED_IF rule
        if eval_metadata_rule "${required_if}"; then
            local val="${CONFIG_VALUES[${var_name}]:-}"

            if is_placeholder "${val}"; then
                log_error "Required configuration variable missing or placeholder: ${var_name} (${prompt_text})"
                failed=1
            fi
        fi
    done

    if [[ "${failed}" -eq 1 ]]; then
        log_error "Generator validation failed. Aborting .env generation due to missing required variables."
        return 1
    fi

    return 0
}

# Auto-generate missing passwords for any CHANGE_ME or placeholder password variables before generating .env
auto_generate_missing_passwords() {
    local secret_vars=(
        "MARIADB_ROOT_PASSWORD|MariaDB Root Password"
        "GRAFANA_ADMIN_PASSWORD|Grafana Admin Password"
        "BACKUP_ENCRYPTION_KEY|Backup Encryption Passphrase"
        "TRAEFIK_DASHBOARD_PASSWORD|Traefik Dashboard Password"
    )

    local entry var_name label val gen_pass
    for entry in "${secret_vars[@]}"; do
        var_name="${entry%%|*}"
        label="${entry#*|}"
        val="${CONFIG_VALUES[${var_name}]:-}"

        if is_placeholder "${val}" || [[ "${val}" == "CHANGE_ME" ]]; then
            gen_pass=$(generate_random_secret "${var_name}" 16)
            CONFIG_VALUES["${var_name}"]="${gen_pass}"
            log_info "Auto-generated random password for ${label}"
            save_credential_to_file "${var_name}" "${label}" "${gen_pass}"
        fi
    done
}

# Compute dynamic TRAEFIK_DASHBOARD_BASIC_AUTH htpasswd hash from user password using fallback chain
compute_traefik_basic_auth() {
    local user="${CONFIG_VALUES[TRAEFIK_DASHBOARD_USER]:-admin}"
    local pass="${CONFIG_VALUES[TRAEFIK_DASHBOARD_PASSWORD]:-}"

    if [[ -z "${pass}" ]] || [[ "${pass}" == "CHANGE_ME" ]]; then
        pass=$(generate_random_secret "TRAEFIK_DASHBOARD_PASSWORD" 16)
        CONFIG_VALUES["TRAEFIK_DASHBOARD_PASSWORD"]="${pass}"
        log_info "Auto-generated random password for Traefik Dashboard Password"
        save_credential_to_file "TRAEFIK_DASHBOARD_PASSWORD" "Traefik Dashboard Password" "${pass}"
    fi

    local hash=""
    local format_name=""

    # CARA B: htpasswd from apache2-utils (bcrypt $2y$)
    if ! command -v htpasswd >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1 && [[ "${EUID:-1000}" -eq 0 ]]; then
            apt-get update -q >/dev/null 2>&1 || true
            apt-get install -y apache2-utils -q >/dev/null 2>&1 || true
        fi
    fi

    if command -v htpasswd >/dev/null 2>&1; then
        local raw
        raw=$(htpasswd -nbB "${user}" "${pass}" 2>/dev/null || true)
        if [[ -n "${raw}" ]]; then
            hash="${raw#*:}"
            format_name="bcrypt (\$2y\$)"
        fi
    fi

    # CARA A: openssl passwd -6 (SHA-512 $6$)
    if [[ -z "${hash}" ]] && command -v openssl >/dev/null 2>&1; then
        hash=$(openssl passwd -6 "${pass}" 2>/dev/null || true)
        if [[ -n "${hash}" ]]; then
            format_name="SHA-512 (\$6\$)"
        fi
    fi

    # CARA C: python3 bcrypt
    if [[ -z "${hash}" ]] && command -v python3 >/dev/null 2>&1; then
        hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'${pass}', bcrypt.gensalt()).decode())" 2>/dev/null || true)
        if [[ -n "${hash}" ]]; then
            format_name="bcrypt"
        fi
    fi

    if [[ -n "${hash}" ]]; then
        # Escape $ to $$ for Docker Compose environment variable substitution
        local escaped_hash="${hash//\$/\$\$}"
        CONFIG_VALUES["TRAEFIK_DASHBOARD_BASIC_AUTH"]="${user}:${escaped_hash}"
        log_success "Generated Traefik basic auth hash (${format_name})"
    else
        log_error "Could not generate Traefik basic auth hash"
    fi
}

# Generate .env file from .env.example template
generate_env_file() {
    local project_root="$1"
    local env_example="${project_root}/.env.example"
    local env_target="${project_root}/.env"

    # Pre-generation requirement assertion
    if ! validate_generator_requirements; then
        return 1
    fi

    if [[ ! -f "${env_example}" ]]; then
        log_error "Template file not found: ${env_example}"
        return 1
    fi

    log_info "Parsing .env.example template..."

    # Pre-compute dynamic configuration values and auto-generate passwords if needed
    auto_generate_missing_passwords
    compute_traefik_basic_auth

    local generated_content=""
    local line key val

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Preserve comments, blank lines, lines without =
        if [[ -z "${line}" ]] || [[ "${line}" =~ ^[[:space:]]*# ]] || [[ "${line}" != *"="* ]]; then
            generated_content+="${line}"$'\n'
            continue
        fi

        # Extract key
        key="${line%%=*}"
        key="${key// /}"

        # If key exists in CONFIG_VALUES, replace value
        if [[ -n "${key}" ]] && [[ -v "CONFIG_VALUES[${key}]" ]]; then
            val="${CONFIG_VALUES[${key}]}"
            if [[ "${val}" =~ [[:space:]] ]] && [[ ! "${val}" =~ ^\".*\"$ ]]; then
                val="\"${val}\""
            fi
            generated_content+="${key}=${val}"$'\n'
        else
            # Preserve original line from .env.example if not explicitly overridden
            generated_content+="${line}"$'\n'
        fi
    done < "${env_example}"

    # Backup existing .env file if it exists
    if [[ -f "${env_target}" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S)
        local backup_path="${env_target}.bak.${timestamp}"
        safe_cp "${env_target}" "${backup_path}"
        log_info "Created timestamped backup: ${backup_path}"
    fi

    # Write generated configuration using write_config
    write_config "${env_target}" "${generated_content}" "600"
    log_success "Generated environment file: ${env_target}"
}
