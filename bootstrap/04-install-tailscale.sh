#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Tailscale VPN Installation & Authentication
# ==============================================================================
#
# Description:
#   Installs and configures Tailscale VPN client from official Tailscale APT
#   repositories. Enables the tailscaled service and authenticates the host node
#   to the Tailnet using TAILSCALE_AUTHKEY and TAILSCALE_HOSTNAME from .env.
#
# Architecture Decision — Network Access & P2P:
#   Tailscale provides zero-config WireGuard mesh VPN access. Running Tailscale
#   before Security Hardening (Step 05) ensures the tailscale0 network interface
#   is active and ready for UFW firewall rule configuration.
#
# Constraints:
#   - MUST be run as root (EUID 0)
#   - All operations MUST be idempotent
#   - TAILSCALE_AUTHKEY is optional (if empty, installation is skipped)
#   - NO modification of SSH or UFW daemon (belongs to Step 05)
#
# Usage:
#   sudo bash bootstrap/04-install-tailscale.sh
#
# ==============================================================================

# === Environment Setup ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ==============================================================================
# CONSTANTS & FILE PATHS
# ==============================================================================

readonly TAILSCALE_KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"
readonly TAILSCALE_SOURCES="/etc/apt/sources.list.d/tailscale.list"

# ==============================================================================
# WORKFLOW FUNCTIONS
# ==============================================================================

# Add Tailscale Official GPG Key and Repository idempotently
add_tailscale_repository() {
    log_info "Configuring official Tailscale repository..."

    if [[ -f "${TAILSCALE_SOURCES}" ]] && [[ -f "${TAILSCALE_KEYRING}" ]]; then
        log_info "Tailscale repository already configured"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would download Tailscale GPG keyring to: ${TAILSCALE_KEYRING}"
        log_dry "Would create APT sources file: ${TAILSCALE_SOURCES}"
        return 0
    fi

    local ubuntu_codename="${VERSION_CODENAME:-}"
    if [[ -z "${ubuntu_codename}" ]]; then
        ubuntu_codename=$(lsb_release -cs 2>/dev/null || echo "noble")
    fi

    log_info "Downloading Tailscale GPG keyring..."
    retry 3 3 curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${ubuntu_codename}.noarmor.gpg" \
        -o "${TAILSCALE_KEYRING}"
    set_permissions "${TAILSCALE_KEYRING}" "644"

    log_info "Creating Tailscale APT list file..."
    retry 3 3 curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${ubuntu_codename}.tailscale-keyring.list" \
        -o "${TAILSCALE_SOURCES}"
    set_permissions "${TAILSCALE_SOURCES}" "644"

    apt_update
    log_success "Tailscale repository successfully configured"
}

# Install Tailscale package idempotently
install_tailscale_package() {
    log_info "Installing Tailscale package..."

    if is_installed "tailscale"; then
        log_info "Tailscale package already installed"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would install package: tailscale"
        return 0
    fi

    install_package "tailscale"
    log_success "Tailscale package ready"
}

# Enable and start tailscaled daemon service
enable_tailscale_service() {
    log_info "Enabling and starting tailscaled systemd service..."

    service_enable "tailscaled"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would start service: tailscaled"
        return 0
    fi

    service_start "tailscaled"
    log_success "tailscaled service active and running"
}

# Authenticate Tailscale node to Tailnet using TAILSCALE_AUTHKEY from .env
authenticate_tailscale_node() {
    local authkey="${TAILSCALE_AUTHKEY:-}"
    local default_host
    default_host=$(hostname 2>/dev/null || echo "bootstrap-server")
    local hostname="${TAILSCALE_HOSTNAME:-${VPN_HOSTNAME:-${default_host}}}"
    local accept_dns="${TAILSCALE_ACCEPT_DNS:-false}"
    local accept_routes="${TAILSCALE_ACCEPT_ROUTES:-true}"
    local enable_ssh="${TAILSCALE_SSH:-false}"

    log_info "Checking Tailscale node authentication status..."

    # Check if already authenticated and connected
    if tailscale status >/dev/null 2>&1; then
        local current_ip
        current_ip=$(tailscale ip -4 2>/dev/null || true)
        if [[ -n "${current_ip}" ]]; then
            log_info "Tailscale node is already authenticated (IPv4: ${current_ip})"
            return 0
        fi
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would authenticate Tailscale node as '${hostname}' with authkey"
        return 0
    fi

    validate_env "TAILSCALE_AUTHKEY"

    log_info "Authenticating Tailscale node with hostname '${hostname}'..."

    local ts_args=(
        "--authkey=${authkey}"
        "--hostname=${hostname}"
        "--accept-dns=${accept_dns}"
    )

    if [[ "${accept_routes}" == "true" ]]; then
        ts_args+=("--accept-routes")
    fi

    if [[ "${enable_ssh}" == "true" ]]; then
        ts_args+=("--ssh")
    fi

    if [[ -n "${TAILSCALE_EXTRA_ARGS:-}" ]]; then
        local extra_args=()
        read -r -a extra_args <<< "${TAILSCALE_EXTRA_ARGS}"
        ts_args+=("${extra_args[@]}")
    fi

    # Authenticate node with non-interactive flags
    tailscale up "${ts_args[@]}"

    log_success "Tailscale node successfully authenticated as '${hostname}'"
}

# Verify Tailscale connectivity and IPv4 allocation
verify_tailscale_connection() {
    local default_host
    default_host=$(hostname 2>/dev/null || echo "bootstrap-server")
    local hostname="${TAILSCALE_HOSTNAME:-${VPN_HOSTNAME:-${default_host}}}"

    log_section "TAILSCALE INSTALLATION VERIFICATION"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would verify Tailscale status and IPv4 address"
        return 0
    fi

    local ts_ip
    local ts_status

    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    ts_status=$(tailscale status --self 2>/dev/null || echo "FAIL")

    if [[ -n "${ts_ip}" ]]; then
        log_success "Tailscale IPv4 Assigned: ${ts_ip}"
    else
        log_warn "Tailscale IPv4 not available yet — node may be pending authorization"
    fi

    if [[ "${ts_status}" != "FAIL" ]]; then
        log_info "Self Status: ${ts_status}"
    else
        log_error "Tailscale verification failed: tailscaled daemon non-responsive"
        exit 1
    fi

    printf '  Tailscale Daemon: Running\n'
    printf '  Tailscale IPv4:   %s\n' "${ts_ip:-Pending}"
    printf '  Hostname:        %s\n' "${hostname}"
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

    if [[ -z "${TAILSCALE_AUTHKEY:-}" ]] || [[ "${TAILSCALE_AUTHKEY}" == "CHANGE_ME" ]]; then
        log_info "Tailscale auth key not configured"
        log_info "Skipping Tailscale installation"
        exit 0
    fi

    print_header "Tailscale Installation" "WireGuard VPN client, daemon service, and Tailnet authentication"

    log_section "Official Repository Setup"
    add_tailscale_repository

    log_section "Tailscale Package Ingestion"
    install_tailscale_package

    log_section "Service Enablement"
    enable_tailscale_service

    log_section "Tailnet Node Authentication"
    authenticate_tailscale_node

    log_section "Tailscale Verification"
    verify_tailscale_connection

    log_success "Tailscale installation completed successfully"
}

main "$@"
