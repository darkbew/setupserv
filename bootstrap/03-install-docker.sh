#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Docker Engine & Compose Installation
# ==============================================================================
#
# Description:
#   Installs Docker Engine (CE) and Docker Compose Plugin from official Docker
#   repositories. Configures production-grade daemon settings, logging limits,
#   default address pools, systemd service enablement, user group attachment,
#   and default container bridge network.
#
# Architecture Decision — Log Driver:
#   Uses json-file log driver with configurable max-size and max-file rotation.
#   Scrapers (such as Promtail / Fluentbit) parse container logs from
#   /var/lib/docker/containers/ in JSON format.
#
# Constraints:
#   - MUST be run as root (EUID 0)
#   - All operations MUST be idempotent
#   - NO static temporary files in /tmp (GPG key streamed securely via pipe)
#   - NO application containers deployed
#
# Usage:
#   sudo bash bootstrap/03-install-docker.sh
#
# ==============================================================================

# === Environment Setup ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ==============================================================================
# CONSTANTS & PACKAGES
# ==============================================================================

readonly DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
readonly DOCKER_SOURCES="/etc/apt/sources.list.d/docker.list"
readonly DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

readonly DEFAULT_DOCKER_PACKAGES=(
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-buildx-plugin"
    "docker-compose-plugin"
)

# ==============================================================================
# WORKFLOW FUNCTIONS
# ==============================================================================

# Remove legacy/conflicting OS Docker packages idempotently
remove_legacy_docker() {
    local old_packages=(
        "docker"
        "docker-engine"
        "docker.io"
        "containerd"
        "runc"
    )

    local to_remove=()
    local pkg

    for pkg in "${old_packages[@]}"; do
        if is_installed "${pkg}"; then
            to_remove+=("${pkg}")
        fi
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log_info "No legacy Docker packages detected"
        return 0
    fi

    log_info "Removing legacy Docker packages: ${to_remove[*]}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would remove legacy packages: ${to_remove[*]}"
        return 0
    fi

    DEBIAN_FRONTEND=noninteractive apt-get remove -y "${to_remove[@]}" > /dev/null 2>&1 || true
    log_success "Removed legacy Docker packages"
}

# Add Docker Official GPG Key and Repository securely via Pipe (No static /tmp files)
add_docker_repository() {
    log_info "Configuring official Docker repository..."

    if [[ -f "${DOCKER_SOURCES}" ]] && [[ -f "${DOCKER_KEYRING}" ]]; then
        log_info "Docker official repository already configured"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would create directory: /etc/apt/keyrings"
        log_dry "Would stream GPG key: https://download.docker.com/linux/ubuntu/gpg → ${DOCKER_KEYRING}"
        log_dry "Would write APT source file: ${DOCKER_SOURCES}"
        return 0
    fi

    safe_mkdir "/etc/apt/keyrings" "755"

    log_info "Downloading Docker GPG key..."
    retry 3 3 curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | gpg --dearmor --yes -o "${DOCKER_KEYRING}"
    set_permissions "${DOCKER_KEYRING}" "644"

    # shellcheck source=/dev/null
    source /etc/os-release
    local arch
    arch=$(dpkg --print-architecture)

    local repo_line
    repo_line=$(printf 'deb [arch=%s signed-by=%s] https://download.docker.com/linux/ubuntu %s stable' \
        "${arch}" "${DOCKER_KEYRING}" "${VERSION_CODENAME}")

    write_config "${DOCKER_SOURCES}" "${repo_line}" "644"
    apt_update

    log_success "Docker official repository successfully added"
}

# Install Docker Engine & Compose packages idempotently
install_docker_packages() {
    local pkg
    local installed_count=0
    local skipped_count=0
    local packages=("${DEFAULT_DOCKER_PACKAGES[@]}")

    if [[ -n "${EXTRA_DOCKER_PACKAGES:-}" ]]; then
        local extra_pkgs=()
        read -r -a extra_pkgs <<< "${EXTRA_DOCKER_PACKAGES}"
        packages+=("${extra_pkgs[@]}")
    fi

    log_info "Installing Docker Engine packages..."

    for pkg in "${packages[@]}"; do
        if is_installed "${pkg}"; then
            skipped_count=$((skipped_count + 1))
        else
            installed_count=$((installed_count + 1))
        fi
        install_package "${pkg}"
    done

    log_success "Docker Engine packages ready (${installed_count} installed, ${skipped_count} skipped)"
}

# Configure /etc/docker/daemon.json with SHA256 comparison and production tuning
configure_docker_daemon() {
    local log_driver="${DOCKER_LOG_DRIVER:-json-file}"
    local max_size="${DOCKER_LOG_MAX_SIZE:-10m}"
    local max_file="${DOCKER_LOG_MAX_FILE:-3}"
    local storage_driver="${DOCKER_STORAGE_DRIVER:-overlay2}"
    local live_restore="${DOCKER_LIVE_RESTORE:-true}"
    local pool_base="${DOCKER_ADDRESS_POOL_BASE:-172.18.0.0/16}"
    local pool_size="${DOCKER_ADDRESS_POOL_SIZE:-24}"

    log_info "Configuring Docker daemon settings in ${DOCKER_DAEMON_JSON}..."

    local content
    content=$(cat <<DAEMON_EOF
{
    "log-driver": "${log_driver}",
    "log-opts": {
        "max-size": "${max_size}",
        "max-file": "${max_file}"
    },
    "storage-driver": "${storage_driver}",
    "live-restore": ${live_restore},
    "default-address-pools": [
        {
            "base": "${pool_base}",
            "size": ${pool_size}
        }
    ]
}
DAEMON_EOF
)

    write_config "${DOCKER_DAEMON_JSON}" "${content}" "644"
}

# Ensure operational deploy user is attached to docker group
attach_deploy_user_to_docker_group() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"

    if ! id "${deploy_user}" &>/dev/null; then
        log_warn "User '${deploy_user}' does not exist — skipping docker group assignment"
        return 0
    fi

    if id -nG "${deploy_user}" 2>/dev/null | grep -qw docker; then
        log_info "User '${deploy_user}' is already a member of 'docker' group"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would add user ${deploy_user} to docker group"
        return 0
    fi

    usermod -aG docker "${deploy_user}"
    log_success "Added '${deploy_user}' to docker group"
}

# Enable systemd services and restart Docker service to apply daemon settings
enable_and_start_docker() {
    log_info "Configuring systemd services for Docker..."

    service_enable "docker"
    service_enable "containerd"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would restart docker.service"
        return 0
    fi

    log_info "Restarting Docker service to apply daemon.json..."
    service_restart "docker"
    log_success "Docker Engine service active and running"
}

# Create default platform Docker network idempotently
create_docker_network() {
    local network_name="${DOCKER_NETWORK_NAME:-${DEFAULT_DOCKER_NETWORK:-bootstrap-net}}"

    log_info "Creating default platform Docker network '${network_name}'..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would create docker network: ${network_name} (bridge)"
        return 0
    fi

    if docker network inspect "${network_name}" >/dev/null 2>&1; then
        log_info "Docker network '${network_name}' already exists"
        return 0
    fi

    docker network create --driver bridge "${network_name}" >/dev/null 2>&1
    log_success "Created Docker bridge network: ${network_name}"
}

# Verify Docker installation metrics and runtime health
verify_docker_installation() {
    local network_name="${DOCKER_NETWORK_NAME:-${DEFAULT_DOCKER_NETWORK:-bootstrap-net}}"

    log_section "DOCKER INSTALLATION VERIFICATION"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would verify Docker engine and compose versions"
        return 0
    fi

    local docker_ver
    local compose_ver
    local log_driver
    local live_restore

    docker_ver=$(docker --version 2>/dev/null || echo "FAIL")
    compose_ver=$(docker compose version 2>/dev/null || echo "FAIL")
    log_driver=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || echo "FAIL")
    live_restore=$(docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null || echo "FAIL")

    if [[ "${docker_ver}" == "FAIL" ]]; then
        log_error "Docker Engine verification failed: docker command non-responsive"
        exit 1
    fi

    if [[ "${compose_ver}" == "FAIL" ]]; then
        log_error "Docker Compose verification failed: docker compose non-responsive"
        exit 1
    fi

    printf '  Docker Engine:   %s\n' "${docker_ver}"
    printf '  Docker Compose:  %s\n' "${compose_ver}"
    printf '  Logging Driver:  %s\n' "${log_driver}"
    printf '  Live Restore:    %s\n' "${live_restore}"
    printf '  Bridge Network:  %s (Active)\n' "${network_name}"
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

    print_header "Docker Engine Installation" "Docker CE, Compose plugin, daemon tuning, network baseline"

    log_section "Cleanup Legacy Packages"
    remove_legacy_docker

    log_section "Official Repository Setup"
    add_docker_repository

    log_section "Docker Package Installation"
    install_docker_packages

    log_section "Daemon Tuning & Group Membership"
    configure_docker_daemon
    attach_deploy_user_to_docker_group

    log_section "Service Enable & Startup"
    enable_and_start_docker

    log_section "Platform Network Creation"
    create_docker_network

    verify_docker_installation
    log_success "Docker Engine & Compose installation completed successfully"
}

main "$@"
