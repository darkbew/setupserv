#!/usr/bin/env bash
# ==============================================================================
# Mitseri Platform — System Update & Base Essentials
# ==============================================================================
#
# Description:
#   Updates the Operating System package repository index, performs safe system
#   upgrades, installs essential base tools, configures Locale and Timezone,
#   and cleans up APT caches.
#
# Constraints:
#   - MUST be run as root (EUID 0)
#   - All operations MUST be idempotent
#   - NO Docker, Podman, Tailscale, or User creation
#   - NO system reboot or network restart
#
# Usage:
#   sudo bash bootstrap/01-system-update.sh
#
# System Requirements:
#   Ubuntu Server 24.04 LTS (Noble Numbat) — Bash 5.2+
#
# ==============================================================================

# === Environment Setup ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ==============================================================================
# ESSENTIAL PACKAGES DEFINITION (48 PACKAGES)
# ==============================================================================

readonly BASE_PACKAGES=(
    # Package Management & SSL Integrity
    "curl"
    "wget"
    "git"
    "ca-certificates"
    "gnupg"
    "lsb-release"
    "software-properties-common"
    "apt-transport-https"
    
    # Text Processing & Data Format Tools
    "jq"
    "unzip"
    "zip"
    "tar"
    "gzip"
    "xz-utils"
    "rsync"
    
    # Text Editors & Basic Tools
    "nano"
    "vim"
    "htop"
    "tree"
    
    # Network Inspection Tools
    "net-tools"
    "iproute2"
    "dnsutils"
    "openssl"
    
    # System Administration & Access Control
    "acl"
    "sudo"
    "ufw"
    "cron"
    "logrotate"
    "bash-completion"
    
    # Build Essentials & Compilers (Needed for native extensions)
    "build-essential"
    "make"
    "gcc"
    "g++"
    "pkg-config"
    "libffi-dev"
    "libssl-dev"
    
    # Python Baseline
    "python3"
    "python3-pip"
    "python3-venv"
    
    # System Localization & Timezone
    "locales"
    "tzdata"
    
    # System Utilities & Diagnostics
    "uuid-runtime"
    "lsof"
    "psmisc"
    "sysstat"
    "bc"
    "screen"
    "tmux"
)

# ==============================================================================
# WORKFLOW FUNCTIONS
# ==============================================================================

# Perform APT Repository Refresh and Safe Package Upgrade
perform_apt_upgrade() {
    log_info "Synchronizing APT package repositories..."
    apt_update

    log_info "Upgrading existing system packages..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would execute: apt-get upgrade -y"
        return 0
    fi

    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q > /dev/null 2>&1
    log_success "System packages successfully upgraded"
}

# Install essential base packages one-by-one idempotently
install_essential_packages() {
    local pkg
    local installed_count=0
    local skipped_count=0

    log_info "Installing ${#BASE_PACKAGES[@]} essential base packages..."

    for pkg in "${BASE_PACKAGES[@]}"; do
        if is_installed "${pkg}"; then
            skipped_count=$((skipped_count + 1))
        else
            installed_count=$((installed_count + 1))
        fi
        install_package "${pkg}"
    done

    log_success "Base packages ready (${installed_count} newly installed, ${skipped_count} skipped/already present)"
}

# Configure System Locale idempotently (en_US.UTF-8)
configure_locale() {
    local target_locale="en_US.UTF-8"

    log_info "Checking system locale configuration..."

    if locale 2>/dev/null | grep -q "LANG=${target_locale}"; then
        log_info "Locale already set to ${target_locale}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would generate and set locale: ${target_locale}"
        return 0
    fi

    log_info "Generating locale ${target_locale}..."
    locale-gen "${target_locale}" > /dev/null 2>&1 || true
    update-locale LANG="${target_locale}" > /dev/null 2>&1 || true
    log_success "Locale configured: ${target_locale}"
}

# Configure System Timezone idempotently
configure_timezone() {
    local target_tz="${TZ:-Asia/Jakarta}"

    log_info "Configuring system timezone..."

    if command -v timedatectl &>/dev/null; then
        local current_tz
        current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")

        if [[ "${current_tz}" == "${target_tz}" ]]; then
            log_info "Timezone already set to ${target_tz}"
            return 0
        fi

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "Would set timezone to: ${target_tz}"
            return 0
        fi

        if timedatectl set-timezone "${target_tz}" 2>/dev/null; then
            log_success "Timezone set to ${target_tz}"
        else
            log_warn "Failed to set timezone to ${target_tz}, falling back to UTC"
            timedatectl set-timezone "UTC" 2>/dev/null || true
        fi
    else
        log_warn "timedatectl not available — skipping timezone configuration"
    fi
}

# Clean up unused packages and APT cache
cleanup_apt_cache() {
    log_info "Cleaning up unused packages and APT cache..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would run: apt-get autoremove, autoclean, clean"
        return 0
    fi

    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q > /dev/null 2>&1 || true
    apt-get autoclean -q > /dev/null 2>&1 || true
    apt-get clean -q > /dev/null 2>&1 || true

    log_success "APT cache successfully cleaned"
}

# Print Summary Report
print_summary_report() {
    local os_version="Unknown"
    local kernel_version="Unknown"
    local current_tz="Unknown"
    local current_lang="Unknown"

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        os_version="${PRETTY_NAME:-Ubuntu 24.04 LTS}"
    fi

    kernel_version=$(uname -r)
    current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
    current_lang=$(locale 2>/dev/null | grep "^LANG=" | cut -d= -f2 || echo "en_US.UTF-8")

    log_section "SYSTEM UPDATE SUMMARY"
    printf '  OS Release:      %s\n' "${os_version}"
    printf '  Kernel Version:  %s\n' "${kernel_version}"
    printf '  System Locale:   %s\n' "${current_lang}"
    printf '  System Timezone: %s\n' "${current_tz}"
    printf '  APT Cache State: Cleaned\n'
    printf '  Status:          Base OS Essentials Ready\n'
    printf '\n'
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

main() {
    check_root

    # Load environment file if present
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        load_env "${env_file}"
        validate_env "TZ"
    fi

    print_header "System Update & Essentials" "APT repository upgrade, base packages, locale, timezone"

    log_section "APT Repository & System Upgrade"
    perform_apt_upgrade

    log_section "Base Essential Packages"
    install_essential_packages

    log_section "Localization & Timezone"
    configure_locale
    configure_timezone

    log_section "APT Maintenance & Cleanup"
    cleanup_apt_cache

    print_summary_report
    log_success "System Update completed successfully"
}

main "$@"
