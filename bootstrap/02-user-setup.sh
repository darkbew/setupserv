#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Deploy User & Identity Setup
# ==============================================================================
#
# Description:
#   Creates the dedicated operational deploy user, sets up passwordless sudoers
#   rules with visudo validation, configures the SSH directory (~/.ssh) with
#   strict permissions (700/600), optionally installs an initial SSH public key,
#   and prepares Docker group membership.
#
# Constraints:
#   - MUST be run as root (EUID 0)
#   - All operations MUST be idempotent
#   - NO Docker installation or SSH daemon modification
#   - NO eval execution for home directory resolution
#
# Usage:
#   sudo bash bootstrap/02-user-setup.sh
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

# Create operational deploy user idempotently
create_deploy_user() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    local user_shell="${DEPLOY_USER_SHELL:-/bin/bash}"

    log_info "Checking existence of user '${deploy_user}'..."

    if id "${deploy_user}" &>/dev/null; then
        log_info "User '${deploy_user}' already exists"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry "Would create user: ${deploy_user} (shell: ${user_shell})"
        return 0
    fi

    if ! command -v "${user_shell}" &>/dev/null; then
        user_shell="/bin/bash"
    fi

    log_info "Creating operational user '${deploy_user}'..."
    useradd \
        --create-home \
        --shell "${user_shell}" \
        --comment "Server Bootstrap Framework Deploy User" \
        "${deploy_user}"

    log_success "Created OS user: ${deploy_user}"
}

# Configure passwordless sudoers drop-in file with visudo syntax validation
configure_sudoers() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    local sudoers_file="/etc/sudoers.d/90-bootstrap-${deploy_user}"

    log_info "Configuring sudoers permissions for '${deploy_user}'..."

    # Ensure deploy user is in sudo group idempotently
    if id -nG "${deploy_user}" 2>/dev/null | grep -qw sudo; then
        log_info "User '${deploy_user}' is already in 'sudo' group"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "Would add user ${deploy_user} to group: sudo"
        else
            usermod -aG sudo "${deploy_user}"
            log_success "Added '${deploy_user}' to group: sudo"
        fi
    fi

    # Build sudoers configuration content
    local content
    content=$(cat <<SUDOERS_EOF
# ==============================================================================
# Server Bootstrap Framework — Sudoers Configuration
# ==============================================================================
# Managed by bootstrap/02-user-setup.sh — Do not edit manually.
# Passwordless sudo for deploy user (required for CI/CD automation & DevOps).
# ==============================================================================

${deploy_user} ALL=(ALL:ALL) NOPASSWD: ALL
SUDOERS_EOF
)

    # Secure temporary file creation using mktemp to prevent symlink race conditions
    local tmp_sudoers
    tmp_sudoers=$(mktemp /tmp/sudoers_test.XXXXXX)

    printf '%s\n' "${content}" > "${tmp_sudoers}"

    if ! visudo -cf "${tmp_sudoers}" >/dev/null 2>&1; then
        rm -f "${tmp_sudoers}"
        log_error "Sudoers syntax validation failed via visudo. Aborting write."
        exit 1
    fi
    rm -f "${tmp_sudoers}"

    # Write config idempotently via write_config (SHA-256 compare + backup)
    write_config "${sudoers_file}" "${content}" "440"

    # Final visudo assertion on live file
    if [[ "${DRY_RUN}" != "true" ]]; then
        if visudo -cf "${sudoers_file}" >/dev/null 2>&1; then
            log_success "Sudoers syntax validated: ${sudoers_file} (440)"
        else
            log_error "Live sudoers file check failed — removing invalid config: ${sudoers_file}"
            rm -f "${sudoers_file}"
            exit 1
        fi
    fi
}

# Configure SSH directory (~/.ssh) and authorized_keys with strict permissions (700/600)
configure_ssh_directory() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    local user_home
    user_home=$(get_user_home "${deploy_user}")
    local ssh_dir="${user_home}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    log_info "Configuring SSH environment for '${deploy_user}' in '${ssh_dir}'..."

    safe_mkdir "${ssh_dir}" "700"
    set_ownership "${ssh_dir}" "${deploy_user}:${deploy_user}"

    if [[ ! -f "${auth_keys}" ]]; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "Would create file: ${auth_keys} (mode 600)"
        else
            touch "${auth_keys}"
            log_info "Created file: ${auth_keys}"
        fi
    fi

    set_permissions "${auth_keys}" "600"
    set_ownership "${auth_keys}" "${deploy_user}:${deploy_user}"

    # Optional initial public key ingestion from environment
    local pubkey="${DEPLOY_USER_PUBKEY:-${INITIAL_SSH_KEY:-}}"
    if [[ -n "${pubkey}" ]]; then
        append_unique_line "${auth_keys}" "${pubkey}"
    fi

    log_success "SSH directory ready: ${ssh_dir} (700) & authorized_keys (600)"
}

# Pre-create Docker group and append deploy user idempotently
prepare_docker_group() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"

    log_info "Preparing 'docker' group membership..."

    if getent group docker >/dev/null 2>&1; then
        log_info "Group 'docker' already exists"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "Would create group: docker"
        else
            groupadd docker
            log_success "Group created: docker"
        fi
    fi

    if id -nG "${deploy_user}" 2>/dev/null | grep -qw docker; then
        log_info "User '${deploy_user}' is already member of group 'docker'"
    else
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry "Would add user ${deploy_user} to group: docker"
        else
            usermod -aG docker "${deploy_user}"
            log_success "Added '${deploy_user}' to group: docker"
        fi
    fi
}

# Verify identity and permission assertions
verify_user_setup() {
    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    local user_home
    user_home=$(get_user_home "${deploy_user}")
    local sudoers_file="/etc/sudoers.d/90-bootstrap-${deploy_user}"

    log_section "DEPLOY USER VERIFICATION REPORT"

    if id "${deploy_user}" &>/dev/null; then
        local user_uid user_gid
        user_uid=$(id -u "${deploy_user}")
        user_gid=$(id -g "${deploy_user}")
        printf '  User Name:       %s (UID: %s, GID: %s)\n' "${deploy_user}" "${user_uid}" "${user_gid}"
    else
        log_error "User '${deploy_user}' missing after setup."
        exit 1
    fi

    printf '  Home Directory:  %s\n' "${user_home}"
    printf '  Sudoers File:    %s (440)\n' "${sudoers_file}"
    printf '  SSH Directory:   %s/.ssh (700)\n' "${user_home}"
    printf '  Authorized Keys: %s/.ssh/authorized_keys (600)\n' "${user_home}"
    printf '  Docker Group:    Member\n'
    printf '\n'
}

# ==============================================================================
# MAIN ORCHESTRATION
# ==============================================================================

main() {
    check_root

    # Load environment configuration
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        load_env "${env_file}"
    fi

    local deploy_user="${DEPLOY_USER:-${OPERATIONAL_USER:-deploy}}"
    print_header "Deploy User Setup" "Creating operational user '${deploy_user}', sudoers, and SSH security"

    log_section "OS User Creation"
    create_deploy_user

    log_section "Sudoers Privilege Configuration"
    configure_sudoers

    log_section "SSH Directory & Key Permissions"
    configure_ssh_directory

    log_section "Docker Group Attachment"
    prepare_docker_group

    verify_user_setup
    log_success "Deploy user setup completed successfully for '${deploy_user}'"
}

main "$@"
