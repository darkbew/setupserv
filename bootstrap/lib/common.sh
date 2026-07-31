#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Enterprise Shared Library Framework
# ==============================================================================
#
# Description:
#   Core infrastructure library providing unified logging, error handling,
#   idempotent config writers, safe file manipulators, package managers,
#   service wrappers, environment loaders, and network resiliency helpers.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib/common.sh"
#
# System Requirements:
#   Ubuntu Server 24.04 LTS (Noble Numbat) — Bash 5.2+
#
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. EXECUTION & SOURCING GUARDS
# ------------------------------------------------------------------------------

# Prevent direct execution of shared library
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This library must be sourced, not executed directly." >&2
    echo "Usage: source ${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Guard against double-sourcing
if [[ -n "${_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
_COMMON_SH_LOADED=1

# ------------------------------------------------------------------------------
# 2. BASH STRICT MODE
# ------------------------------------------------------------------------------
set -Eeuo pipefail

# ------------------------------------------------------------------------------
# 3. GLOBAL CONSTANTS
# ------------------------------------------------------------------------------

readonly FRAMEWORK_VERSION="0.1.0"
readonly FRAMEWORK_NAME="Server Bootstrap Framework"

# Hardware thresholds
# shellcheck disable=SC2034
readonly DEFAULT_MIN_RAM_MB=2048
# shellcheck disable=SC2034
readonly DEFAULT_REC_RAM_MB=8192
# shellcheck disable=SC2034
readonly DEFAULT_MIN_DISK_GB=20
# shellcheck disable=SC2034
readonly DEFAULT_WARN_DISK_GB=50
readonly FRAMEWORK_SUPPORTED_OS=("22.04" "24.04")

# ------------------------------------------------------------------------------
# 4. TERMINAL COLORS (ANSI-C Quoting)
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
    readonly RED=$'\033[0;31m'
    readonly GREEN=$'\033[0;32m'
    readonly YELLOW=$'\033[1;33m'
    readonly BLUE=$'\033[0;34m'
    readonly CYAN=$'\033[0;36m'
    readonly BOLD=$'\033[1m'
    readonly NC=$'\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly BOLD=''
    readonly NC=''
fi

# ------------------------------------------------------------------------------
# 5. RUNTIME ENVIRONMENT CONFIGURATION
# ------------------------------------------------------------------------------

DRY_RUN="${DRY_RUN:-false}"
LOG_DIR="${LOG_DIR:-/var/log/bootstrap-framework}"

# Fallback to local project logs directory if /var/log/bootstrap-framework is not writeable
if [[ ! -w "${LOG_DIR}" ]] && ! mkdir -p "${LOG_DIR}" 2>/dev/null; then
    LOG_DIR="${PROJECT_ROOT:-.}/logs/platform"
fi

if [[ -z "${LOG_FILE:-}" ]]; then
    _log_timestamp=$(date +%Y%m%d-%H%M%S)
    LOG_FILE="${LOG_DIR}/bootstrap-${_log_timestamp}.log"
    unset _log_timestamp
fi

# ------------------------------------------------------------------------------
# 6. LOGGING ENGINE
# ------------------------------------------------------------------------------

_log_init_done=""

# Core logging function supporting stdout/stderr and persistent file logging
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Initialize log directory on first write
    if [[ -z "${_log_init_done}" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        mkdir -p "${LOG_DIR}" 2>/dev/null || true
        _log_init_done=1
    fi

    # Write to persistent log file cleanly without throwing redirection errors to stdout/stderr
    if [[ "${DRY_RUN}" != "true" ]] && [[ -n "${LOG_FILE:-}" ]]; then
        { printf '[%s] [%-7s] %s\n' "${timestamp}" "${level}" "${message}" >> "${LOG_FILE}"; } 2>/dev/null || true
    fi

    # Write to console with ANSI colors
    case "${level}" in
        INFO)    printf '%s[INFO]%s    %s\n' "${BLUE}" "${NC}" "${message}" ;;
        SUCCESS) printf '%s[OK]%s      %s\n' "${GREEN}" "${NC}" "${message}" ;;
        WARN)    printf '%s[WARN]%s    %s\n' "${YELLOW}" "${NC}" "${message}" ;;
        ERROR)   printf '%s[ERROR]%s   %s\n' "${RED}" "${NC}" "${message}" >&2 ;;
        DRY)     printf '%s[DRY-RUN]%s %s\n' "${CYAN}" "${NC}" "${message}" ;;
        *)       printf '[%s]   %s\n' "${level}" "${message}" ;;
    esac
}

log_info()    { _log "INFO" "$@"; }
log_success() { _log "SUCCESS" "$@"; }
log_warn()    { _log "WARN" "$@"; }
log_error()   { _log "ERROR" "$@"; }
log_dry()     { _log "DRY" "$@"; }

log_section() {
    local title="$1"
    printf '\n'
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '%s  %s%s\n' "${BOLD}" "${title}" "${NC}"
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '\n'
    if [[ "${DRY_RUN}" != "true" ]] && [[ -n "${LOG_FILE:-}" ]]; then
        { printf '\n== %s ==\n' "${title}" >> "${LOG_FILE}"; } 2>/dev/null || true
    fi
}

print_header() {
    local script_name="$1"
    local description="${2:-}"
    printf '\n'
    printf '%s──────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
    printf '%s  %s v%s%s\n' "${BOLD}" "${FRAMEWORK_NAME}" "${FRAMEWORK_VERSION}" "${NC}"
    printf '%s  %s%s\n' "${BOLD}" "${script_name}" "${NC}"
    if [[ -n "${description}" ]]; then
        printf '  %s\n' "${description}"
    fi
    if [[ "${DRY_RUN}" == "true" ]]; then
        printf '  %s*** DRY RUN MODE — no changes will be made ***%s\n' "${CYAN}" "${NC}"
    fi
    printf '%s──────────────────────────────────────────────────────%s\n' "${BOLD}" "${NC}"
    printf '\n'
}

# ------------------------------------------------------------------------------
# 7. ERROR HANDLING & TRAP ENGINE
# ------------------------------------------------------------------------------

# Global ERR trap handler providing full call stack tracing
trap_error() {
    local exit_code=$?
    local line="${1:-?}"
    local cmd="${2:-unknown}"

    # Prevent recursive error loops inside trap
    set +e
    trap - ERR

    printf '\n'
    log_error "━━━ FATAL ERROR ENCOUNTERED ━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_error "Command:   ${cmd}"
    log_error "Exit Code: ${exit_code}"
    log_error "Line:      ${line}"
    log_error ""
    log_error "Call Stack Trace:"

    local i=0
    local frame_info
    while true; do
        if ! frame_info=$(caller "${i}" 2>/dev/null); then
            break
        fi
        log_error "  [${i}] ${frame_info}"
        i=$((i + 1))
    done

    log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit "${exit_code}"
}

trap 'trap_error "${LINENO}" "${BASH_COMMAND}"' ERR

# ------------------------------------------------------------------------------
# 8. ENVIRONMENT & SYSTEM VALIDATORS
# ------------------------------------------------------------------------------

# Verify running with root superuser privileges
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be executed as root (use: sudo bash $0)"
        exit 1
    fi
}

# Validate supported Ubuntu LTS release
check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS — /etc/os-release not found"
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_error "Unsupported OS: ${ID:-unknown}. Only Ubuntu Server LTS is supported."
        exit 1
    fi

    local version_supported=false
    local supported
    for supported in "${FRAMEWORK_SUPPORTED_OS[@]}"; do
        if [[ "${VERSION_ID:-}" == "${supported}" ]]; then
            version_supported=true
            break
        fi
    done

    if [[ "${version_supported}" != "true" ]]; then
        log_error "Unsupported Ubuntu version: ${VERSION_ID:-unknown}"
        log_error "Supported: ${FRAMEWORK_SUPPORTED_OS[*]}"
        exit 1
    fi

    log_success "OS: Ubuntu ${VERSION_ID} LTS (${VERSION_CODENAME:-})"
}

# Safely resolve user home directory without eval
get_user_home() {
    local target_user="$1"
    local user_home

    user_home=$(getent passwd "${target_user}" 2>/dev/null | cut -d: -f6)
    if [[ -z "${user_home}" ]]; then
        echo "/home/${target_user}"
    else
        echo "${user_home}"
    fi
}

# Parse key-value environment file safely without code execution
load_env() {
    local env_file="${1:-.env}"

    if [[ ! -f "${env_file}" ]]; then
        log_error "Environment file not found: ${env_file}"
        log_error "Run: cp .env.example .env  then edit .env"
        exit 1
    fi

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip empty lines, comments, lines without =
        [[ -z "${line}" ]] && continue
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" != *"="* ]] && continue

        # Split on first =
        key="${line%%=*}"
        value="${line#*=}"

        # Trim whitespace from key
        key="${key// /}"

        # Strip surrounding quotes from value
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        # Skip empty keys
        [[ -z "${key}" ]] && continue

        export "${key}=${value}"
    done < "${env_file}"

    log_success "Environment loaded: ${env_file}"
}

# Validate required variables are present and not default CHANGE_ME
validate_env() {
    local missing=0
    local var_name

    for var_name in "$@"; do
        if [[ -z "${!var_name:-}" ]]; then
            log_error "Required variable not set: ${var_name}"
            missing=$((missing + 1))
        elif [[ "${!var_name}" == "CHANGE_ME" ]]; then
            log_error "Variable not configured: ${var_name} (still CHANGE_ME)"
            missing=$((missing + 1))
        fi
    done

    if [[ "${missing}" -gt 0 ]]; then
        log_error "${missing} required variable(s) missing. Edit .env file."
        exit 1
    fi
}

# Hostname format validator (RFC 1123 compliant)
validate_hostname() {
    local host_str="$1"
    if [[ "${host_str}" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}$ ]]; then
        return 0
    else
        return 1
    fi
}

# FQDN Domain format validator
validate_domain() {
    local domain_str="$1"
    if [[ "${domain_str}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        return 0
    else
        return 1
    fi
}

# IPv4 Address format validator
validate_ip() {
    local ip_str="$1"
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ "${ip_str}" =~ ${rx} ]]; then
        local IFS='.'
        local -a octets
        read -r -a octets <<< "${ip_str}"
        [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]
        return $?
    else
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 9. SAFE FILE & PERMISSION MANIPULATORS
# ------------------------------------------------------------------------------

# Safe directory creation respecting DRY_RUN
safe_mkdir() {
    local dir_path="$1"
    local mode="${2:-755}"

    if [[ -d "${dir_path}" ]]; then
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would create directory: ${dir_path} (mode ${mode})"
        return 0
    fi

    mkdir -p "${dir_path}"
    chmod "${mode}" "${dir_path}"
    log_info "Created directory: ${dir_path} (${mode})"
}

# Safe file copy respecting DRY_RUN
safe_cp() {
    local src="$1"
    local dest="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would copy: ${src} → ${dest}"
        return 0
    fi

    cp -p "${src}" "${dest}"
    log_info "Copied: ${src} → ${dest}"
}

# Safe file move respecting DRY_RUN
safe_mv() {
    local src="$1"
    local dest="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would move: ${src} → ${dest}"
        return 0
    fi

    mv "${src}" "${dest}"
    log_info "Moved: ${src} → ${dest}"
}

# Safe file removal respecting DRY_RUN
safe_rm() {
    local target="$1"

    if [[ ! -e "${target}" ]]; then
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would remove: ${target}"
        return 0
    fi

    rm -f "${target}"
    log_info "Removed: ${target}"
}

# Set file/directory permissions safely
set_permissions() {
    local target="$1"
    local mode="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would chmod ${mode} ${target}"
        return 0
    fi

    chmod "${mode}" "${target}"
    log_info "Permissions set: ${target} (${mode})"
}

# Set file/directory ownership safely
set_ownership() {
    local target="$1"
    local owner_group="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would chown ${owner_group} ${target}"
        return 0
    fi

    chown "${owner_group}" "${target}"
    log_info "Ownership set: ${target} (${owner_group})"
}

# Append a line to a file if it does not already exist (Idempotent)
append_unique_line() {
    local target="$1"
    local line="$2"

    if [[ -f "${target}" ]] && grep -Fxq "${line}" "${target}" 2>/dev/null; then
        log_info "Line already present in ${target}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would append line to ${target}: ${line}"
        return 0
    fi

    printf '%s\n' "${line}" >> "${target}"
    log_success "Appended line to ${target}"
}

# Replace matching line or append if absent (Idempotent)
replace_or_append() {
    local target="$1"
    local regex_match="$2"
    local replacement_line="$3"

    if [[ ! -f "${target}" ]]; then
        write_config "${target}" "${replacement_line}" "644"
        return 0
    fi

    if grep -qE "${regex_match}" "${target}" 2>/dev/null; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "Would replace pattern in ${target} with: ${replacement_line}"
            return 0
        fi
        backup_config "${target}"
        sed -i -E "s|${regex_match}|${replacement_line}|g" "${target}"
        log_success "Replaced line in ${target}"
    else
        append_unique_line "${target}" "${replacement_line}"
    fi
}

# ------------------------------------------------------------------------------
# 10. CONFIGURATION & HASHING ENGINE
# ------------------------------------------------------------------------------

# Create timestamped backup of configuration file before modification
backup_config() {
    local file="$1"

    [[ ! -f "${file}" ]] && return 0

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup="${file}.bak.${timestamp}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would backup: ${file} → ${backup}"
        return 0
    fi

    cp -p "${file}" "${backup}"
    log_info "Backup created: ${file} → ${backup}"
}

# Write configuration file idempotently using SHA-256 hash comparison
write_config() {
    local target="$1"
    local content="$2"
    local permissions="${3:-644}"

    local new_hash
    new_hash=$(printf '%s' "${content}" | sha256sum | cut -d' ' -f1)

    if [[ -f "${target}" ]]; then
        local old_hash
        old_hash=$(sha256sum "${target}" | cut -d' ' -f1)
        if [[ "${new_hash}" == "${old_hash}" ]]; then
            log_info "Config unchanged: ${target}"
            return 0
        fi
        backup_config "${target}"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would write config: ${target} (${permissions})"
        return 0
    fi

    local parent_dir
    parent_dir=$(dirname "${target}")
    mkdir -p "${parent_dir}"

    printf '%s' "${content}" > "${target}"
    chmod "${permissions}" "${target}"
    log_success "Written config: ${target}"
}

# ------------------------------------------------------------------------------
# 11. PACKAGE & APT WRAPPERS
# ------------------------------------------------------------------------------

# Check command existence in system PATH
check_dependency() {
    command -v "${1}" &>/dev/null
}

# Fast dpkg-query package status checker
is_installed() {
    dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -q "ok installed"
}

# Run apt-get update with network retry wrapper
apt_update() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would run: apt-get update"
        return 0
    fi

    log_info "Updating APT package index..."
    retry 3 5 apt-get update -q > /dev/null 2>&1
    log_success "APT package index updated"
}

# Install APT package idempotently
install_package() {
    local pkg="$1"

    if is_installed "${pkg}"; then
        log_info "Package '${pkg}' already installed"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would install package: ${pkg}"
        return 0
    fi

    log_info "Installing package: ${pkg}..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${pkg}" > /dev/null 2>&1
    log_success "Installed package: ${pkg}"
}

# ------------------------------------------------------------------------------
# 12. SYSTEMD SERVICE WRAPPERS
# ------------------------------------------------------------------------------

service_enable() {
    local service_name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would enable service: ${service_name}"
        return 0
    fi
    systemctl enable "${service_name}" --quiet 2>/dev/null || true
    log_info "Service enabled: ${service_name}"
}

service_disable() {
    local service_name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would disable service: ${service_name}"
        return 0
    fi
    systemctl disable "${service_name}" --quiet 2>/dev/null || true
    log_info "Service disabled: ${service_name}"
}

service_start() {
    local service_name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would start service: ${service_name}"
        return 0
    fi
    systemctl start "${service_name}" 2>/dev/null
    log_success "Service started: ${service_name}"
}

service_stop() {
    local service_name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would stop service: ${service_name}"
        return 0
    fi
    systemctl stop "${service_name}" 2>/dev/null || true
    log_info "Service stopped: ${service_name}"
}

service_restart() {
    local service_name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would restart service: ${service_name}"
        return 0
    fi
    systemctl restart "${service_name}" 2>/dev/null
    log_success "Service restarted: ${service_name}"
}

service_reload() {
    local service_name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would reload service: ${service_name}"
        return 0
    fi
    systemctl reload "${service_name}" 2>/dev/null || systemctl restart "${service_name}" 2>/dev/null
    log_success "Service reloaded: ${service_name}"
}

# ------------------------------------------------------------------------------
# 13. NETWORK & UTILITY HELPERS
# ------------------------------------------------------------------------------

# Exponential backoff retry execution wrapper
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2

    local attempt=1
    while true; do
        if "$@"; then
            return 0
        fi

        if [[ "${attempt}" -ge "${max_attempts}" ]]; then
            log_error "Command failed after ${max_attempts} attempts: $*"
            return 1
        fi

        log_warn "Attempt ${attempt}/${max_attempts} failed, retrying in ${delay}s..."
        sleep "${delay}"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

# Download file safely via curl with retry wrapper
download_file() {
    local url="$1"
    local dest="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would download: ${url} → ${dest}"
        return 0
    fi

    log_info "Downloading: ${url}..."
    retry 3 3 curl -fsSL "${url}" -o "${dest}"
    log_success "Downloaded: ${dest}"
}

# Generic command runner respecting DRY_RUN mode
run_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would execute: $*"
        return 0
    fi
    "$@"
}
