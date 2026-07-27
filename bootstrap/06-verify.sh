#!/usr/bin/env bash
# ==============================================================================
# Mitseri Platform — Bootstrap Verification
# ==============================================================================
#
# Comprehensive post-bootstrap validation.
# Checks every component installed by Milestone 1 bootstrap scripts.
#
# Output: PASS / WARN / FAIL for each check
# Exit:   0 if no FAILs, 1 if any FAIL
#
# This script does NOT modify the system.
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
            for v in "22.04" "24.04"; do
                [[ "${VERSION_ID:-}" == "${v}" ]] && supported=true
            done
            if [[ "${supported}" == "true" ]]; then
                check_pass "Ubuntu ${VERSION_ID} LTS (${VERSION_CODENAME:-})"
            else
                check_fail "Ubuntu ${VERSION_ID:-unknown} — not LTS"
            fi
        else
            check_fail "OS: ${ID:-unknown} — Ubuntu required"
        fi
    else
        check_fail "Cannot detect OS"
    fi

    # Kernel
    local kernel
    kernel=$(uname -r)
    check_pass "Kernel: ${kernel}"

    # Architecture
    local arch
    arch=$(uname -m)
    if [[ "${arch}" == "x86_64" ]]; then
        check_pass "Architecture: ${arch}"
    else
        check_fail "Architecture: ${arch} (x86_64 required)"
    fi

    # Timezone
    local tz_expected="${TZ:-Asia/Jakarta}"
    local tz_current
    tz_current=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
    if [[ "${tz_current}" == "${tz_expected}" ]]; then
        check_pass "Timezone: ${tz_current}"
    else
        check_fail "Timezone: ${tz_current} (expected ${tz_expected})"
    fi

    # Locale
    local lang
    lang=$(locale 2>/dev/null | grep "^LANG=" | cut -d= -f2)
    if [[ "${lang}" == "en_US.UTF-8" ]]; then
        check_pass "Locale: ${lang}"
    else
        check_warn "Locale: ${lang:-not set} (expected en_US.UTF-8)"
    fi
}

verify_hardware() {
    print_section "HARDWARE"

    # Memory
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    if [[ $((mem_kb / 1024)) -ge 8192 ]]; then
        check_pass "Memory: ${mem_gb}GB"
    else
        check_fail "Memory: ${mem_gb}GB (minimum 8GB)"
    fi

    # Disk space
    local free_kb free_gb
    free_kb=$(df --output=avail / | tail -n1 | tr -d ' ')
    free_gb=$((free_kb / 1024 / 1024))
    if [[ "${free_gb}" -ge 50 ]]; then
        check_pass "Disk free: ${free_gb}GB"
    else
        check_fail "Disk free: ${free_gb}GB (minimum 50GB)"
    fi

    # Filesystem
    local fs_type
    fs_type=$(findmnt -n -o FSTYPE /)
    if [[ "${fs_type}" == "ext4" ]] || [[ "${fs_type}" == "xfs" ]]; then
        check_pass "Filesystem: ${fs_type}"
    else
        check_warn "Filesystem: ${fs_type} (ext4/xfs recommended)"
    fi

    # SSD detection
    local root_src disk_name rotational
    root_src=$(findmnt -n -o SOURCE /)
    disk_name=$(lsblk -nd -o PKNAME "${root_src}" 2>/dev/null) || true
    if [[ -n "${disk_name}" ]] && [[ -f "/sys/block/${disk_name}/queue/rotational" ]]; then
        rotational=$(cat "/sys/block/${disk_name}/queue/rotational")
        if [[ "${rotational}" == "0" ]]; then
            check_pass "Disk type: SSD (${disk_name})"
        else
            check_warn "Disk type: HDD (${disk_name})"
        fi
    else
        check_warn "Disk type: could not detect"
    fi

    # Swap
    local swap_total
    swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
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

    # timesyncd service
    if systemctl is-active systemd-timesyncd > /dev/null 2>&1; then
        check_pass "systemd-timesyncd: active"
    else
        check_fail "systemd-timesyncd: not running"
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
    local root_login="yes"
    if [[ -f /etc/ssh/sshd_config.d/99-mitseri-hardening.conf ]]; then
        root_login=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config.d/99-mitseri-hardening.conf 2>/dev/null | awk '{print $2}')
    fi
    if [[ "${root_login}" == "no" ]]; then
        check_pass "SSH PermitRootLogin: no"
    else
        check_fail "SSH PermitRootLogin: ${root_login:-not set}"
    fi

    # SSH PasswordAuthentication (Phase 1 = yes is expected)
    local pwd_auth="not set"
    if [[ -f /etc/ssh/sshd_config.d/99-mitseri-hardening.conf ]]; then
        pwd_auth=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config.d/99-mitseri-hardening.conf 2>/dev/null | awk '{print $2}')
    fi
    if [[ "${pwd_auth}" == "no" ]]; then
        check_pass "SSH PasswordAuthentication: no"
    elif [[ "${pwd_auth}" == "yes" ]]; then
        check_warn "SSH PasswordAuthentication: yes (Phase 2 pending)"
    else
        check_fail "SSH PasswordAuthentication: ${pwd_auth}"
    fi

    # SSH AllowUsers
    local allow_users
    allow_users=$(grep -i "^AllowUsers" /etc/ssh/sshd_config.d/99-mitseri-hardening.conf 2>/dev/null | awk '{print $2}') || true
    local deploy_user="${DEPLOY_USER:-deploy}"
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

    local deploy_user="${DEPLOY_USER:-deploy}"

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
        check_pass "User in docker group"
    else
        check_warn "User not in docker group"
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
    local log_driver
    log_driver=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null)
    if [[ "${log_driver}" == "json-file" ]]; then
        check_pass "Log driver: ${log_driver}"
    else
        check_warn "Log driver: ${log_driver} (expected json-file)"
    fi

    # Live restore
    local live_restore
    live_restore=$(docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null)
    if [[ "${live_restore}" == "true" ]]; then
        check_pass "Live restore: enabled"
    else
        check_warn "Live restore: disabled"
    fi

    # Storage driver
    local storage_driver
    storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null)
    if [[ "${storage_driver}" == "overlay2" ]]; then
        check_pass "Storage driver: ${storage_driver}"
    else
        check_warn "Storage driver: ${storage_driver} (expected overlay2)"
    fi
}

verify_tailscale() {
    print_section "TAILSCALE"

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

    local config_file="/etc/systemd/journald.conf.d/99-mitseri.conf"

    if [[ -f "${config_file}" ]]; then
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
    else
        check_warn "Journald config: ${config_file} not found"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    check_root
    load_env "${PROJECT_ROOT}/.env"

    printf '\n'
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '%s  MITSERI PLATFORM — BOOTSTRAP VERIFICATION         %s\n' "${BOLD}" "${NC}"
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"

    verify_system
    verify_hardware
    verify_time
    verify_network
    verify_security
    verify_user
    verify_docker
    verify_tailscale
    verify_journald

    # Summary
    printf '\n'
    printf '%s══════════════════════════════════════════════════════%s\n' "${BOLD}" "${NC}"
    printf '  RESULT: %s%d PASS%s | %s%d WARN%s | %s%d FAIL%s\n' \
        "${GREEN}" "${PASS_COUNT}" "${NC}" \
        "${YELLOW}" "${WARN_COUNT}" "${NC}" \
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
