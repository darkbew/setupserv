#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Bootstrap Verification
# ==============================================================================
#
# Description:
#   Comprehensive post-bootstrap validation.
#   Checks every component installed by bootstrap framework scripts (00–05).
#
# Output: PASS / WARN / FAIL / SKIP for each check
# Exit:   0 if no FAILs, 1 if any FAIL
#
# This script is READ-ONLY — it does NOT modify the system.
#
# Usage:
#   sudo bash bootstrap/06-verify.sh
#
# ==============================================================================

# === Environment Setup ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Override strict mode — verification continues on individual failures
set +e
trap - ERR

# ==============================================================================
# COUNTERS AND CHECK HELPERS
# ==============================================================================

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

check_pass() {
    printf '    %s[PASS]%s %s\n' "${GREEN}" "${NC}" "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

check_warn() {
    printf '    %s[WARN]%s %s\n' "${YELLOW}" "${NC}" "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

check_fail() {
    printf '    %s[FAIL]%s %s\n' "${RED}" "${NC}" "$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_skip() {
    printf '    %s[SKIP]%s %s\n' "${CYAN}" "${NC}" "$1"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

print_section() {
    printf '\n  %s%s%s\n' "${BOLD}" "$1" "${NC}"
}

# ==============================================================================
# VERIFICATION CHECKS
# ==============================================================================

verify_system() {
    print_section "SYSTEM"

    # Ubuntu version
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "${ID:-}" == "ubuntu" ]]; then
            local supported=false
            local v
            for v in "22.04" "24.04"; do
                [[ "${VERSION_ID:-}" == "${v}" ]] && supported=true
            done
            if [[ "${supported}" == "true" ]]; then
                check_pass "Ubuntu ${VERSION_ID} LTS (${VERSION_CODENAME:-})"
            else
                check_fail "Ubuntu ${VERSION_ID:-unknown} — not supported LTS"
            fi
        else
            check_fail "OS: ${ID:-unknown} — Ubuntu required"
        fi
    else
        check_fail "Cannot detect OS (/etc/os-release missing)"
    fi

    # Kernel
    local kernel
    kernel=$(uname -r)
    check_pass "Kernel: ${kernel}"

    # Architecture (x86_64, amd64, aarch64, arm64)
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64|aarch64|arm64)
            check_pass "Architecture: ${arch}"
            ;;
        *)
            check_fail "Architecture: ${arch} (supported: x86_64, amd64, aarch64, arm64)"
            ;;
    esac

    # Timezone
    local tz_expected="${TZ:-${SYSTEM_TIMEZONE:-UTC}}"
    local tz_current
    tz_current=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
    if [[ "${tz_current}" == "${tz_expected}" ]]; then
        check_pass "Timezone: ${tz_current}"
    else
        check_warn "Timezone: ${tz_current} (expected ${tz_expected})"
    fi

    # Locale
    local lang_expected="${LOCALE:-${SYSTEM_LOCALE:-en_US.UTF-8}}"
    local lang=""
    local locale_out
    locale_out=$(locale 2>/dev/null || true)
    if [[ "${locale_out}" =~ LANG=([^[:space:]]+) ]]; then
        lang="${BASH_REMATCH[1]}"
    fi

    if [[ "${lang}" == "${lang_expected}" ]]; then
        check_pass "Locale: ${lang}"
    else
        check_warn "Locale: ${lang:-not set} (expected ${lang_expected})"
    fi
}

verify_hardware() {
    print_section "HARDWARE"

    local min_ram_mb="${PREFLIGHT_MIN_RAM_MB:-${DEFAULT_MIN_RAM_MB:-2048}}"
    local min_disk_gb="${PREFLIGHT_MIN_DISK_GB:-${DEFAULT_MIN_DISK_GB:-20}}"

    # Memory
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))
    local mem_gb=$((mem_mb / 1024))
    if [[ "${mem_mb}" -ge "${min_ram_mb}" ]]; then
        check_pass "Memory: ${mem_gb}GB"
    else
        check_fail "Memory: ${mem_gb}GB (minimum ${min_ram_mb}MB required)"
    fi

    # Disk space
    local free_kb free_gb
    free_kb=$(df --output=avail / 2>/dev/null | tail -n1 | tr -d ' ')
    free_gb=$((free_kb / 1024 / 1024))
    if [[ "${free_gb}" -ge "${min_disk_gb}" ]]; then
        check_pass "Disk free: ${free_gb}GB"
    else
        check_fail "Disk free: ${free_gb}GB (minimum ${min_disk_gb}GB required)"
    fi

    # Filesystem
    local fs_type
    fs_type=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
    if [[ "${fs_type}" == "ext4" ]] || [[ "${fs_type}" == "xfs" ]]; then
        check_pass "Filesystem: ${fs_type}"
    else
        check_warn "Filesystem: ${fs_type} (ext4/xfs recommended)"
    fi

    # SSD detection
    local root_src disk_name rotational
    root_src=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
    disk_name=$(lsblk -nd -o PKNAME "${root_src}" 2>/dev/null || true)
    if [[ -n "${disk_name}" ]] && [[ -f "/sys/block/${disk_name}/queue/rotational" ]]; then
        rotational=$(cat "/sys/block/${disk_name}/queue/rotational" 2>/dev/null || echo "1")
        if [[ "${rotational}" == "0" ]]; then
            check_pass "Disk type: SSD/NVMe (${disk_name})"
        else
            check_warn "Disk type: HDD (${disk_name})"
        fi
    else
        check_warn "Disk type: could not detect"
    fi

    # Swap
    local swap_total
    swap_total=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    local swappiness
    swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "?")
    if [[ "${swap_total}" -gt 0 ]]; then
        local swap_gb=$((swap_total / 1024 / 1024))
        check_pass "Swap: ${swap_gb}GB (swappiness=${swappiness})"
    else
        check_warn "Swap: none configured"
    fi
}

verify_time() {
    print_section "TIME SYNCHRONIZATION"

    # systemd-timesyncd service
    if systemctl is-active systemd-timesyncd > /dev/null 2>&1; then
        check_pass "systemd-timesyncd: active"
    else
        check_warn "systemd-timesyncd: not active (checking alternative NTP service)"
    fi

    # NTP sync status
    local ntp_sync
    ntp_sync=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo "no")
    if [[ "${ntp_sync}" == "yes" ]]; then
        check_pass "Clock synchronized: yes"
    else
        check_warn "Clock synchronized: no (may sync shortly)"
    fi
}

verify_network() {
    print_section "NETWORK"

    # Internet
    if curl -sfL --connect-timeout 5 --max-time 10 -o /dev/null "https://archive.ubuntu.com" 2>/dev/null; then
        check_pass "Internet connectivity"
    else
        check_fail "Internet connectivity"
    fi

    # DNS
    if getent ahosts archive.ubuntu.com > /dev/null 2>&1; then
        check_pass "DNS resolution"
    else
        check_fail "DNS resolution"
    fi

    # IPv4 forwarding (required for Docker)
    local ip_forward
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [[ "${ip_forward}" == "1" ]]; then
        check_pass "IPv4 forwarding: enabled"
    else
        check_fail "IPv4 forwarding: disabled (Docker needs this)"
    fi
}

verify_security() {
    print_section "SECURITY"

    # UFW
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        check_pass "UFW: active"

        # Check default policy
        if ufw status verbose 2>/dev/null | grep -q "deny (incoming)"; then
            check_pass "UFW default: deny incoming"
        else
            check_warn "UFW default: not deny incoming"
        fi
    else
        check_fail "UFW: not active"
    fi

    # fail2ban
    if systemctl is-active fail2ban > /dev/null 2>&1; then
        check_pass "fail2ban: running"
    else
        check_fail "fail2ban: not running"
    fi

    # SSH PermitRootLogin
    local ssh_config="/etc/ssh/sshd_config.d/99-bootstrap-hardening.conf"
    local root_login="yes"
    if [[ -f "${ssh_config}" ]]; then
        root_login=$(grep -i "^PermitRootLogin" "${ssh_config}" 2>/dev/null | awk '{print $2}')
    fi
    if [[ "${root_login}" == "no" ]]; then
        check_pass "SSH PermitRootLogin: no"
    else
        check_fail "SSH PermitRootLogin: ${root_login:-not set}"
    fi

    # SSH PasswordAuthentication
    local pwd_auth="not set"
    if [[ -f "${ssh_config}" ]]; then
        pwd_auth=$(grep -i "^PasswordAuthentication" "${ssh_config}" 2>/dev/null | awk '{print $2}')
    fi
    if [[ "${pwd_auth}" == "no" ]]; then
        check_pass "SSH PasswordAuthentication: no"
    elif [[ "${pwd_auth}" == "yes" ]]; then
        check_warn "SSH PasswordAuthentication: yes (Phase 1 active)"
    else
        check_fail "SSH PasswordAuthentication: ${pwd_auth}"
    fi

    # SSH AllowUsers
    local allow_users=""
    if [[ -f "${ssh_config}" ]]; then
        allow_users=$(grep -i "^AllowUsers" "${ssh_config}" 2>/dev/null | awk '{print $2}') || true
    fi
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    if [[ "${allow_users}" == "${deploy_user}" ]]; then
        check_pass "SSH AllowUsers: ${allow_users}"
    else
        check_warn "SSH AllowUsers: ${allow_users:-not configured}"
    fi

    # Unattended upgrades
    if systemctl is-enabled unattended-upgrades > /dev/null 2>&1; then
        check_pass "Unattended upgrades: enabled"
    else
        check_fail "Unattended upgrades: not enabled"
    fi

    # Sysctl hardening
    local syncookies
    syncookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "0")
    if [[ "${syncookies}" == "1" ]]; then
        check_pass "Sysctl: tcp_syncookies enabled"
    else
        check_warn "Sysctl: tcp_syncookies not enabled"
    fi
}

verify_user() {
    print_section "DEPLOY USER"

    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"

    # User exists
    if id "${deploy_user}" > /dev/null 2>&1; then
        check_pass "User '${deploy_user}' exists"
    else
        check_fail "User '${deploy_user}' not found"
        return
    fi

    # In sudo group
    if id -nG "${deploy_user}" 2>/dev/null | grep -qw sudo; then
        check_pass "User in sudo group"
    else
        check_fail "User not in sudo group"
    fi

    # In docker group
    if id -nG "${deploy_user}" 2>/dev/null | grep -qw docker; then
        check_pass "User '${deploy_user}' in docker group"
    else
        check_fail "User '${deploy_user}' not in docker group"
    fi

    # Non-root Docker Socket Access
    if command -v docker >/dev/null 2>&1; then
        if sudo -u "${deploy_user}" -H docker info >/dev/null 2>&1; then
            check_pass "User '${deploy_user}' non-root Docker socket access: active"
        else
            check_warn "User '${deploy_user}' in docker group, but active SSH session requires logout/login"
        fi
    fi


    # SSH directory
    local user_home
    user_home=$(get_user_home "${deploy_user}")
    if [[ -d "${user_home}/.ssh" ]]; then
        local ssh_perms
        ssh_perms=$(stat -c '%a' "${user_home}/.ssh" 2>/dev/null)
        if [[ "${ssh_perms}" == "700" ]]; then
            check_pass "SSH directory: ${user_home}/.ssh (700)"
        else
            check_warn "SSH directory: permissions ${ssh_perms} (expected 700)"
        fi
    else
        check_warn "SSH directory: not found"
    fi
}

verify_docker() {
    print_section "DOCKER"

    # Docker Engine
    if command -v docker > /dev/null 2>&1; then
        local docker_ver
        docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        check_pass "Docker Engine: ${docker_ver}"
    else
        check_fail "Docker Engine: not installed"
        return
    fi

    # Docker Compose
    if docker compose version > /dev/null 2>&1; then
        local compose_ver
        compose_ver=$(docker compose version 2>/dev/null | awk '{print $NF}')
        check_pass "Docker Compose: ${compose_ver}"
    else
        check_fail "Docker Compose: not installed"
    fi

    # Docker daemon running
    if docker info > /dev/null 2>&1; then
        check_pass "Docker daemon: running"
    else
        check_fail "Docker daemon: not running"
        return
    fi

    # Log driver
    local expected_log_driver="${DOCKER_LOG_DRIVER:-json-file}"
    local log_driver
    log_driver=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null)
    if [[ "${log_driver}" == "${expected_log_driver}" ]]; then
        check_pass "Log driver: ${log_driver}"
    else
        check_warn "Log driver: ${log_driver} (expected ${expected_log_driver})"
    fi

    # Live restore
    local expected_live_restore="${DOCKER_LIVE_RESTORE:-true}"
    local live_restore
    live_restore=$(docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null)
    if [[ "${live_restore}" == "${expected_live_restore}" ]]; then
        check_pass "Live restore: ${live_restore}"
    else
        check_warn "Live restore: ${live_restore} (expected ${expected_live_restore})"
    fi

    # Storage driver
    local expected_storage_driver="${DOCKER_STORAGE_DRIVER:-overlay2}"
    local storage_driver
    storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null)
    if [[ "${storage_driver}" == "${expected_storage_driver}" ]]; then
        check_pass "Storage driver: ${storage_driver}"
    else
        check_warn "Storage driver: ${storage_driver} (expected ${expected_storage_driver})"
    fi

    # Docker bridge network
    local network_name="${DOCKER_NETWORK_NAME:-${DEFAULT_DOCKER_NETWORK:-bootstrap-net}}"
    if docker network inspect "${network_name}" >/dev/null 2>&1; then
        check_pass "Bridge network: ${network_name} (active)"
    else
        check_warn "Bridge network: ${network_name} (not found)"
    fi
}

verify_tailscale() {
    print_section "TAILSCALE"

    # If auth key was not configured, Tailscale installation was skipped
    if [[ -z "${TAILSCALE_AUTHKEY:-}" ]] || [[ "${TAILSCALE_AUTHKEY:-}" == "CHANGE_ME" ]]; then
        check_skip "Tailscale not configured"
        return 0
    fi

    # Tailscale installed
    if command -v tailscale > /dev/null 2>&1; then
        check_pass "Tailscale: installed"
    else
        check_fail "Tailscale: not installed"
        return
    fi

    # tailscaled running
    if systemctl is-active tailscaled > /dev/null 2>&1; then
        check_pass "tailscaled: running"
    else
        check_fail "tailscaled: not running"
        return
    fi

    # Tailscale IP
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null) || true
    if [[ -n "${ts_ip}" ]]; then
        check_pass "Tailscale IP: ${ts_ip}"
    else
        check_warn "Tailscale IP: not connected"
    fi
}

verify_journald() {
    print_section "JOURNALD"

    local config_file="/etc/systemd/journald.conf.d/99-bootstrap.conf"

    if [[ ! -f "${config_file}" ]]; then
        check_warn "Journald config: ${config_file} not present"
        return 0
    fi

    # Check SystemMaxUse
    local max_use
    max_use=$(grep -i "^SystemMaxUse" "${config_file}" 2>/dev/null | cut -d= -f2)
    if [[ -n "${max_use}" ]]; then
        check_pass "SystemMaxUse: ${max_use}"
    else
        check_warn "SystemMaxUse: not configured"
    fi

    # Check Compress
    local compress
    compress=$(grep -i "^Compress" "${config_file}" 2>/dev/null | cut -d= -f2)
    if [[ "${compress}" == "yes" ]]; then
        check_pass "Compression: enabled"
    else
        check_warn "Compression: not enabled"
    fi
}

verify_repository_location() {
    print_section "REPOSITORY LOCATION"

    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    local target_dir="/opt/setupserv"

    # Directory exists
    if [[ -d "${target_dir}" ]]; then
        check_pass "Platform directory: ${target_dir} exists"
    else
        check_warn "Platform directory: ${target_dir} not found (repository not migrated yet)"
        return 0
    fi

    # Ownership check
    local dir_owner
    dir_owner=$(stat -c '%U' "${target_dir}" 2>/dev/null || echo "unknown")
    if [[ "${dir_owner}" == "${deploy_user}" ]]; then
        check_pass "Directory ownership: ${deploy_user}"
    else
        check_warn "Directory ownership: ${dir_owner} (expected ${deploy_user})"
    fi

    # Essential files exist
    if [[ -f "${target_dir}/Makefile" ]]; then
        check_pass "Makefile: present in ${target_dir}"
    else
        check_warn "Makefile: not found in ${target_dir}"
    fi

    if [[ -f "${target_dir}/.env" ]]; then
        check_pass ".env: present in ${target_dir}"
    else
        check_warn ".env: not found in ${target_dir}"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    check_root

    # Load environment file if present
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        load_env "${env_file}"
    fi

    printf '\n'
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '%s  SERVER BOOTSTRAP FRAMEWORK — BOOTSTRAP VERIFICATION %s\n' "${BOLD}" "${NC}"
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"

    verify_system
    verify_hardware
    verify_time
    verify_network
    verify_security
    verify_user
    verify_docker
    verify_repository_location
    verify_tailscale
    verify_journald

    # Summary
    printf '\n'
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '  RESULT: %s%d PASS%s | %s%d WARN%s | %s%d SKIP%s | %s%d FAIL%s\n' \
        "${GREEN}" "${PASS_COUNT}" "${NC}" \
        "${YELLOW}" "${WARN_COUNT}" "${NC}" \
        "${CYAN}" "${SKIP_COUNT}" "${NC}" \
        "${RED}" "${FAIL_COUNT}" "${NC}"
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '\n'

    # Exit code
    if [[ "${FAIL_COUNT}" -gt 0 ]]; then
        log_error "${FAIL_COUNT} check(s) FAILED — review and fix before proceeding"
        exit 1
    fi

    if [[ "${WARN_COUNT}" -gt 0 ]]; then
        log_warn "${WARN_COUNT} warning(s) — review recommended"
    fi

    log_success "Bootstrap verification complete"
}

main "$@"
