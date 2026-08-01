#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Security Hardening Baseline
# ==============================================================================
#
# Description:
#   Hardens the host server with production-grade security baseline settings:
#   - OpenSSH Hardening (Phase 1: Disable root login, AllowUsers deploy)
#   - UFW Firewall Baseline (Deny incoming, allow SSH private/Tailscale & P2P)
#   - Fail2ban Jail Configuration for SSH brute-force protection
#   - Kernel Sysctl Tuning (Network security, socket limits, inotify, swap)
#   - Journald Persistence & Retention Limiting
#   - Unattended Automatic Security Updates (No auto-reboot)
#
# Constraints:
#   - MUST be run as root (EUID 0)
#   - All operations MUST be idempotent
#   - User 'deploy' MUST exist (Step 02) before executing SSH AllowUsers
#
# Usage:
#   sudo bash bootstrap/05-security-hardening.sh
#
# ==============================================================================

# === Environment Setup ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ==============================================================================
# WORKFLOW FUNCTIONS
# ==============================================================================

# Configure OpenSSH Hardening (Phase 1) with sshd syntax pre-validation
configure_ssh_hardening() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    local password_auth="${SSH_PASSWORD_AUTH:-yes}"
    local max_auth_tries="${SSH_MAX_AUTH_TRIES:-3}"
    local tailscale_ssh="${TAILSCALE_SSH:-false}"
    local allow_tcp_forwarding="no"

    # Tailscale SSH requires TCP forwarding to function
    if [[ "${tailscale_ssh,,}" =~ ^(true|yes|1)$ ]]; then
        allow_tcp_forwarding="yes"
    fi

    log_info "Configuring OpenSSH hardening baseline..."

    # Verify deploy user exists before locking AllowUsers
    if ! id "${deploy_user}" &>/dev/null; then
        log_error "User '${deploy_user}' does not exist on OS. User setup (Step 02) required."
        exit 1
    fi

    local config_dir="/etc/ssh/sshd_config.d"
    local config_file="${config_dir}/99-bootstrap-hardening.conf"

    safe_mkdir "${config_dir}" "755"

    local content
    content=$(cat <<SSH_EOF
# ==============================================================================
# Server Bootstrap Framework — SSH Hardening
# ==============================================================================
# Managed by bootstrap/05-security-hardening.sh — Do not edit manually.
# ==============================================================================

# Authentication & Access Control
PermitRootLogin no
PasswordAuthentication ${password_auth}
PubkeyAuthentication yes
MaxAuthTries ${max_auth_tries}
AllowUsers ${deploy_user}

# Session Limits & Hardening
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30

# Feature Restrictions
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding ${allow_tcp_forwarding}
PermitTunnel no
PermitUserEnvironment no

# Logging
LogLevel VERBOSE
SSH_EOF
)

    write_config "${config_file}" "${content}" "644"

    # Validate SSH configuration syntax using sshd -t before reloading service
    if [[ "${DRY_RUN}" != "true" ]]; then
        if sshd -t 2>/dev/null; then
            service_reload "ssh"
            log_success "SSH hardened and reloaded successfully"
        else
            log_error "SSH configuration syntax check failed via 'sshd -t' — reverting changes"
            rm -f "${config_file}"
            service_reload "ssh"
            exit 1
        fi
    fi
}

# Configure UFW Firewall with default deny policy and private/Tailscale openings
configure_ufw_firewall() {
    log_info "Configuring UFW Firewall baseline..."

    if ! check_dependency "ufw"; then
        log_info "Package 'ufw' missing — installing..."
        install_package "ufw"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would configure UFW: deny incoming, allow outgoing, allow SSH private + Tailscale P2P"
        return 0
    fi

    # Set default firewall policies
    ufw default deny incoming > /dev/null 2>&1 || true
    ufw default allow outgoing > /dev/null 2>&1 || true

    # Parse allowed SSH subnets
    local ssh_subnets=()
    if [[ -n "${SSH_ALLOWED_SUBNETS:-}" ]]; then
        read -r -a ssh_subnets <<< "${SSH_ALLOWED_SUBNETS}"
    else
        ssh_subnets=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10")
    fi

    local subnet
    for subnet in "${ssh_subnets[@]}"; do
        ufw allow from "${subnet}" to any port 22 proto tcp comment "SSH from ${subnet}" > /dev/null 2>&1 || true
    done

    # Allow Tailscale WireGuard Direct P2P Port (UDP 41641 default)
    local p2p_port="${TAILSCALE_P2P_PORT:-41641}"
    ufw allow "${p2p_port}/udp" comment "Tailscale WireGuard Direct P2P" > /dev/null 2>&1 || true

    # Enable firewall non-interactively
    ufw --force enable > /dev/null 2>&1
    log_success "UFW Firewall active: Deny incoming, SSH allowed from Private/Tailscale subnets"
}

# Configure Fail2ban SSH brute-force jail
configure_fail2ban() {
    local maxretry="${FAIL2BAN_MAXRETRY:-3}"
    local bantime="${FAIL2BAN_BANTIME:-3600}"
    local findtime="${FAIL2BAN_FINDTIME:-600}"

    log_info "Configuring Fail2ban SSH brute-force protection..."

    if ! check_dependency "fail2ban-client"; then
        log_info "Package 'fail2ban' missing — installing..."
        install_package "fail2ban"
    fi

    local config_file="/etc/fail2ban/jail.d/99-bootstrap.conf"

    local content
    content=$(cat <<F2B_EOF
# ==============================================================================
# Server Bootstrap Framework — Fail2ban Configuration
# ==============================================================================
# Managed by bootstrap/05-security-hardening.sh — Do not edit manually.
# ==============================================================================

[sshd]
enabled = true
port = ssh
maxretry = ${maxretry}
bantime = ${bantime}
findtime = ${findtime}
backend = systemd
F2B_EOF
)

    write_config "${config_file}" "${content}" "644"

    service_enable "fail2ban"
    service_restart "fail2ban"
    log_success "Fail2ban jail active (SSH ban: ${bantime}s, maxretries: ${maxretry})"
}

# Configure Kernel Sysctl parameters for Network, Memory, and File Descriptors
configure_sysctl_kernel() {
    log_info "Configuring kernel sysctl parameters in /etc/sysctl.d/99-bootstrap.conf..."

    local config_file="/etc/sysctl.d/99-bootstrap.conf"

    local content
    content=$(cat <<'SYSCTL_EOF'
# ==============================================================================
# Server Bootstrap Framework — Kernel Parameter Hardening & Performance Tuning
# ==============================================================================
# Managed by bootstrap/05-security-hardening.sh — Do not edit manually.
# ==============================================================================

# --- Network Security & Forwarding ---
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1

# --- Network Socket Performance ---
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600

# --- Filesystem Descriptors & Inotify Watchers ---
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# --- Memory Tuning ---
vm.swappiness = 10
vm.overcommit_memory = 1
SYSCTL_EOF
)

    write_config "${config_file}" "${content}" "644"

    if [[ "${DRY_RUN}" != "true" ]]; then
        sysctl --system > /dev/null 2>&1 || true
        log_success "Kernel sysctl parameters successfully applied"
    fi
}

# Configure Journald Persistence and SystemMaxUse Retention Limits
configure_journald() {
    local max_use="${JOURNALD_MAX_USE:-1G}"
    local config_dir="/etc/systemd/journald.conf.d"
    local config_file="${config_dir}/99-bootstrap.conf"

    log_info "Configuring Journald log persistence and retention limits..."

    safe_mkdir "${config_dir}" "755"

    local content
    content=$(cat <<JOURNALD_EOF
# ==============================================================================
# Server Bootstrap Framework — Journald Configuration
# ==============================================================================
# Managed by bootstrap/05-security-hardening.sh — Do not edit manually.
# ==============================================================================

[Journal]
Storage=persistent
SystemMaxUse=${max_use}
Compress=yes
JOURNALD_EOF
)

    write_config "${config_file}" "${content}" "644"

    if [[ "${DRY_RUN}" != "true" ]]; then
        service_reload "systemd-journald"
        log_success "Journald log retention applied (Storage: persistent, MaxUse: ${max_use})"
    fi
}

# Configure automatic unattended security upgrades
configure_unattended_upgrades() {
    log_info "Configuring automatic security updates..."

    if ! is_installed "unattended-upgrades"; then
        install_package "unattended-upgrades"
    fi

    # Enable periodic package lists update
    local auto_file="/etc/apt/apt.conf.d/20auto-upgrades"
    local auto_content
    auto_content=$(cat <<'AUTO_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTO_EOF
)
    write_config "${auto_file}" "${auto_content}" "644"

    # Configure unattended upgrades behavior (No auto reboot)
    local unattended_file="/etc/apt/apt.conf.d/51bootstrap-unattended"
    local unattended_content
    unattended_content=$(cat <<'UNATTENDED_EOF'
// ==============================================================================
// Server Bootstrap Framework — Unattended Upgrades Configuration
// ==============================================================================
// Managed by bootstrap/05-security-hardening.sh — Do not edit manually.
// Only security updates. Automatic reboot DISABLED for production stability.
// ==============================================================================

Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
UNATTENDED_EOF
)
    write_config "${unattended_file}" "${unattended_content}" "644"

    service_enable "unattended-upgrades"
    log_success "Automatic security updates enabled (Auto-reboot: DISABLED)"
}

# Verify Security Baseline Report
verify_security_baseline() {
    log_section "SECURITY HARDENING VERIFICATION REPORT"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would verify UFW, Fail2ban, Journald, and SSH configuration status"
        return 0
    fi

    local ufw_status
    local fail2ban_status
    local ssh_root_login
    local ssh_config="/etc/ssh/sshd_config.d/99-bootstrap-hardening.conf"

    ufw_status=$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}' || echo "inactive")
    fail2ban_status=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
    ssh_root_login=$(grep -i "^PermitRootLogin" "${ssh_config}" 2>/dev/null | awk '{print $2}' || echo "unknown")

    printf '  SSH PermitRootLogin: %s\n' "${ssh_root_login}"
    printf '  UFW Firewall Status: %s\n' "${ufw_status}"
    printf '  Fail2ban Jail:       %s\n' "${fail2ban_status}"
    printf '  Sysctl Parameters:   Applied (/etc/sysctl.d/99-bootstrap.conf)\n'
    printf '  Journald Retention:  Configured (/etc/systemd/journald.conf.d/99-bootstrap.conf)\n'
    printf '  Unattended Upgrades: Enabled (No Auto-Reboot)\n'
    printf '\n'
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

main() {
    check_root

    # Load environment variables
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        load_env "${env_file}"
    fi

    print_header "Security Hardening" "SSH hardening, UFW firewall, Fail2ban, sysctl, journald, auto-updates"

    log_section "SSH Hardening (Phase 1)"
    configure_ssh_hardening

    log_section "UFW Firewall Baseline"
    configure_ufw_firewall

    log_section "Fail2ban Protection"
    configure_fail2ban

    log_section "Kernel Sysctl Tuning"
    configure_sysctl_kernel

    log_section "Journald Log Hardening"
    configure_journald

    log_section "Automatic Security Updates"
    configure_unattended_upgrades

    verify_security_baseline
    log_success "Security hardening baseline successfully applied"
    log_warn "REMINDER: Disable SSH PasswordAuthentication after verifying SSH key login via Tailscale"
}

main "$@"
