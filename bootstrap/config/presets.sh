#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Presets Module
# ==============================================================================
#
# Description:
#   Deployment presets (Development, Staging, Production, Custom) that
#   pre-populate CONFIG_VALUES defaults before interactive review or prompting.
#
# Constraints:
#   - Must be sourced by config-wizard.sh
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_PRESETS_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_PRESETS_SH_LOADED=1

# Ensure global associative array exists
declare -A CONFIG_VALUES 2>/dev/null || true

# Apply Development Preset (Minimal resource footprint)
apply_preset_development() {
    CONFIG_VALUES["PRESET_NAME"]="Development"
    CONFIG_VALUES["INSTALL_DOCKER"]="yes"
    CONFIG_VALUES["DOCKER_NETWORK_NAME"]="bootstrap-net"
    CONFIG_VALUES["DOCKER_LOG_MAX_SIZE"]="10m"
    CONFIG_VALUES["DOCKER_LOG_MAX_FILE"]="3"
    CONFIG_VALUES["RESTART_POLICY"]="unless-stopped"

    CONFIG_VALUES["PERMIT_ROOT_LOGIN"]="no"
    CONFIG_VALUES["SSH_PASSWORD_AUTH"]="yes"
    CONFIG_VALUES["ENABLE_UFW"]="yes"
    CONFIG_VALUES["ENABLE_FAIL2BAN"]="no"

    CONFIG_VALUES["INSTALL_TAILSCALE"]="no"
    CONFIG_VALUES["TAILSCALE_AUTHKEY"]=""
    CONFIG_VALUES["TAILSCALE_HOSTNAME"]="${CONFIG_VALUES[HOSTNAME]:-bootstrap-server}"

    CONFIG_VALUES["INSTALL_MONITORING"]="no"
    CONFIG_VALUES["ENABLE_GRAFANA"]="no"
    CONFIG_VALUES["ENABLE_PROMETHEUS"]="no"
    CONFIG_VALUES["ENABLE_LOKI"]="no"
    CONFIG_VALUES["ENABLE_PROMTAIL"]="no"
    CONFIG_VALUES["ENABLE_NODE_EXPORTER"]="no"
    CONFIG_VALUES["ENABLE_CADVISOR"]="no"
    CONFIG_VALUES["ENABLE_UPTIME_KUMA"]="no"

    CONFIG_VALUES["INSTALL_BACKUP"]="no"
    CONFIG_VALUES["INSTALL_TRAEFIK"]="no"
    CONFIG_VALUES["INSTALL_CLOUDFLARE_TUNNEL"]="no"
}

# Apply Staging Preset (Balanced testing environment)
apply_preset_staging() {
    CONFIG_VALUES["PRESET_NAME"]="Staging"
    CONFIG_VALUES["INSTALL_DOCKER"]="yes"
    CONFIG_VALUES["DOCKER_NETWORK_NAME"]="bootstrap-net"
    CONFIG_VALUES["DOCKER_LOG_MAX_SIZE"]="20m"
    CONFIG_VALUES["DOCKER_LOG_MAX_FILE"]="5"
    CONFIG_VALUES["RESTART_POLICY"]="unless-stopped"

    CONFIG_VALUES["PERMIT_ROOT_LOGIN"]="no"
    CONFIG_VALUES["SSH_PASSWORD_AUTH"]="yes"
    CONFIG_VALUES["ENABLE_UFW"]="yes"
    CONFIG_VALUES["ENABLE_FAIL2BAN"]="yes"

    CONFIG_VALUES["INSTALL_TAILSCALE"]="yes"
    CONFIG_VALUES["TAILSCALE_AUTHKEY"]="CHANGE_ME"
    CONFIG_VALUES["TAILSCALE_HOSTNAME"]="${CONFIG_VALUES[HOSTNAME]:-staging-server}"

    CONFIG_VALUES["INSTALL_MONITORING"]="yes"
    CONFIG_VALUES["ENABLE_GRAFANA"]="yes"
    CONFIG_VALUES["ENABLE_PROMETHEUS"]="yes"
    CONFIG_VALUES["ENABLE_LOKI"]="yes"
    CONFIG_VALUES["ENABLE_PROMTAIL"]="yes"
    CONFIG_VALUES["ENABLE_NODE_EXPORTER"]="yes"
    CONFIG_VALUES["ENABLE_CADVISOR"]="yes"
    CONFIG_VALUES["ENABLE_UPTIME_KUMA"]="yes"

    CONFIG_VALUES["INSTALL_BACKUP"]="no"
    CONFIG_VALUES["INSTALL_TRAEFIK"]="yes"
    CONFIG_VALUES["INSTALL_CLOUDFLARE_TUNNEL"]="no"
}

# Apply Production Preset (Enterprise hardened full stack)
apply_preset_production() {
    CONFIG_VALUES["PRESET_NAME"]="Production"
    CONFIG_VALUES["INSTALL_DOCKER"]="yes"
    CONFIG_VALUES["DOCKER_NETWORK_NAME"]="bootstrap-net"
    CONFIG_VALUES["DOCKER_LOG_MAX_SIZE"]="50m"
    CONFIG_VALUES["DOCKER_LOG_MAX_FILE"]="10"
    CONFIG_VALUES["RESTART_POLICY"]="unless-stopped"

    CONFIG_VALUES["PERMIT_ROOT_LOGIN"]="no"
    CONFIG_VALUES["SSH_PASSWORD_AUTH"]="yes"
    CONFIG_VALUES["ENABLE_UFW"]="yes"
    CONFIG_VALUES["ENABLE_FAIL2BAN"]="yes"

    CONFIG_VALUES["INSTALL_TAILSCALE"]="yes"
    CONFIG_VALUES["TAILSCALE_AUTHKEY"]="CHANGE_ME"
    CONFIG_VALUES["TAILSCALE_HOSTNAME"]="${CONFIG_VALUES[HOSTNAME]:-bootstrap-server}"

    CONFIG_VALUES["INSTALL_MONITORING"]="yes"
    CONFIG_VALUES["ENABLE_GRAFANA"]="yes"
    CONFIG_VALUES["ENABLE_PROMETHEUS"]="yes"
    CONFIG_VALUES["ENABLE_LOKI"]="yes"
    CONFIG_VALUES["ENABLE_PROMTAIL"]="yes"
    CONFIG_VALUES["ENABLE_NODE_EXPORTER"]="yes"
    CONFIG_VALUES["ENABLE_CADVISOR"]="yes"
    CONFIG_VALUES["ENABLE_UPTIME_KUMA"]="yes"

    CONFIG_VALUES["INSTALL_BACKUP"]="yes"
    CONFIG_VALUES["BACKUP_SCHEDULE"]="0 2 * * *"
    CONFIG_VALUES["BACKUP_LOCAL_RETENTION_DAYS"]="7"
    CONFIG_VALUES["BACKUP_REMOTE_NAME"]="gdrive"
    CONFIG_VALUES["BACKUP_REMOTE_PATH"]="bootstrap-backups"

    CONFIG_VALUES["INSTALL_TRAEFIK"]="yes"
    CONFIG_VALUES["INSTALL_CLOUDFLARE_TUNNEL"]="no"
}

# Apply Custom Preset (Interactive configuration for all options)
apply_preset_custom() {
    CONFIG_VALUES["PRESET_NAME"]="Custom"
}
