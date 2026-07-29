#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Metadata Registry
# ==============================================================================
#
# Description:
#   Declarative metadata registry for all configurable environment variables.
#   Adding a new variable requires adding a single line to CONFIG_METADATA.
#   No engine logic or UI prompt code is allowed in this file.
#
# Entry Format:
#   VAR_NAME|SECTION|PROMPT_TEXT|DESCRIPTION|DEFAULT_VAL|VALIDATOR|REQUIRED|SECRET|CONDITION
#
# Constraints:
#   - Must be sourced by config-wizard.sh
#   - Must adhere to set -Eeuo pipefail
#
# ==============================================================================

# Guard against double-sourcing
if [[ -n "${_CONFIG_WIZARD_METADATA_SH_LOADED:-}" ]]; then
    return 0
fi
_CONFIG_WIZARD_METADATA_SH_LOADED=1

# Declarative metadata registry table
readonly CONFIG_METADATA=(
    # --- Section 1: General ---
    "HOSTNAME|1_general|Server Hostname|RFC 1123 compliant server hostname|bootstrap-server|validate_hostname|true|false|"
    "TZ|1_general|Server Timezone|IANA format timezone (e.g. Asia/Jakarta)|Asia/Jakarta|validate_timezone|true|false|"
    "DOMAIN|1_general|Primary Domain|FQDN domain name for server services|example.com|validate_domain|true|false|"
    "DEPLOY_USER|1_general|Deploy User|Non-root operational user (cannot be root)|deploy|validate_username|true|false|"
    "SSH_PORT|1_general|SSH Port|SSH daemon listening port|22|validate_port|true|false|"

    # --- Section 2: Docker ---
    "INSTALL_DOCKER|2_docker|Install Docker Engine?|Docker CE container runtime|yes|validate_boolean|true|false|"
    "DOCKER_NETWORK_NAME|2_docker|Docker Network Name|Bridge network name for Docker services|bootstrap-net|validate_hostname|true|false|INSTALL_DOCKER"
    "DOCKER_LOG_MAX_SIZE|2_docker|Docker Log Max Size|Maximum container log file size|10m|validate_docker_log_size|true|false|INSTALL_DOCKER"
    "DOCKER_LOG_MAX_FILE|2_docker|Docker Log Max Files|Number of rotated container log files|3|validate_positive_integer|true|false|INSTALL_DOCKER"
    "RESTART_POLICY|2_docker|Container Restart Policy|Default Docker restart policy|unless-stopped|validate_docker_restart|true|false|INSTALL_DOCKER"

    # --- Section 3: Security ---
    "PERMIT_ROOT_LOGIN|3_security|Permit SSH Root Login?|Disable direct SSH root authentication|no|validate_boolean|true|false|"
    "SSH_PASSWORD_AUTH|3_security|SSH Password Auth (Phase 1)?|Allow SSH password login during initial setup|yes|validate_boolean|true|false|"
    "ENABLE_UFW|3_security|Enable UFW Firewall?|Host UFW firewall default deny incoming|yes|validate_boolean|true|false|"
    "ENABLE_FAIL2BAN|3_security|Enable Fail2ban?|Fail2ban SSH brute-force jail protection|yes|validate_boolean|true|false|"

    # --- Section 4: Tailscale ---
    "INSTALL_TAILSCALE|4_tailscale|Install Tailscale Mesh VPN?|WireGuard mesh VPN node registration|yes|validate_boolean|true|false|"
    "TAILSCALE_AUTHKEY|4_tailscale|Tailscale Auth Key|Tailscale auth key (CHANGE_ME or empty to skip)|CHANGE_ME|none|false|secret|INSTALL_TAILSCALE"
    "TAILSCALE_HOSTNAME|4_tailscale|Tailscale Hostname|Server node name on Tailnet|bootstrap-server|validate_hostname|true|false|INSTALL_TAILSCALE"
    "TAILSCALE_ACCEPT_ROUTES|4_tailscale|Accept Subnet Routes?|Accept subnet routes from Tailnet|true|validate_boolean|true|false|INSTALL_TAILSCALE"
    "TAILSCALE_ACCEPT_DNS|4_tailscale|Accept Tailnet DNS?|Use Tailnet DNS resolution|false|validate_boolean|true|false|INSTALL_TAILSCALE"
    "TAILSCALE_SSH|4_tailscale|Enable Tailscale SSH?|Enable Tailscale embedded SSH server|false|validate_boolean|true|false|INSTALL_TAILSCALE"

    # --- Section 5: Monitoring ---
    "INSTALL_MONITORING|5_monitoring|Install Monitoring Stack?|Prometheus & Grafana monitoring suite|no|validate_boolean|true|false|"
    "ENABLE_GRAFANA|5_monitoring|Enable Grafana?|Grafana dashboard service|yes|validate_boolean|true|false|INSTALL_MONITORING"
    "GRAFANA_ADMIN_USER|5_monitoring|Grafana Admin Username|Grafana dashboard admin username|admin|validate_username|true|false|ENABLE_GRAFANA"
    "GRAFANA_ADMIN_PASSWORD|5_monitoring|Grafana Admin Password|Grafana admin password (min 12 chars)|CHANGE_ME|validate_password|true|secret|ENABLE_GRAFANA"
    "ENABLE_PROMETHEUS|5_monitoring|Enable Prometheus?|Prometheus metrics collector|yes|validate_boolean|true|false|INSTALL_MONITORING"
    "ENABLE_LOKI|5_monitoring|Enable Loki?|Loki log aggregation engine|yes|validate_boolean|true|false|INSTALL_MONITORING"
    "ENABLE_PROMTAIL|5_monitoring|Enable Promtail?|Promtail log collector agent|yes|validate_boolean|true|false|INSTALL_MONITORING"
    "ENABLE_NODE_EXPORTER|5_monitoring|Enable Node Exporter?|Node host metrics exporter|yes|validate_boolean|true|false|INSTALL_MONITORING"
    "ENABLE_CADVISOR|5_monitoring|Enable cAdvisor?|Container metrics exporter|yes|validate_boolean|true|false|INSTALL_MONITORING"
    "ENABLE_UPTIME_KUMA|5_monitoring|Enable Uptime Kuma?|Uptime Kuma status monitor|yes|validate_boolean|true|false|INSTALL_MONITORING"

    # --- Section 6: Backup ---
    "INSTALL_BACKUP|6_backup|Install Backup Stack?|Automated rclone backup system|no|validate_boolean|true|false|"
    "BACKUP_SCHEDULE|6_backup|Backup Schedule|Cron schedule string (e.g. 0 2 * * *)|0 2 * * *|validate_cron|true|false|INSTALL_BACKUP"
    "BACKUP_LOCAL_RETENTION_DAYS|6_backup|Local Backup Retention (Days)|Local backup retention period|7|validate_positive_integer|true|false|INSTALL_BACKUP"
    "BACKUP_REMOTE_NAME|6_backup|Remote Storage Name|Rclone remote target name|gdrive|validate_hostname|true|false|INSTALL_BACKUP"
    "BACKUP_REMOTE_PATH|6_backup|Remote Storage Path|Remote directory path for backups|bootstrap-backups|none|true|false|INSTALL_BACKUP"
    "BACKUP_ENCRYPTION_KEY|6_backup|Backup Encryption Passphrase|Passphrase for backup encryption (min 12 chars)|CHANGE_ME|validate_password|true|secret|INSTALL_BACKUP"

    # --- Section 7: Reverse Proxy ---
    "INSTALL_TRAEFIK|7_traefik|Install Traefik Proxy?|Traefik v3 reverse proxy|yes|validate_boolean|true|false|"
    "TRAEFIK_DASHBOARD_USER|7_traefik|Traefik Dashboard User|Traefik admin user|admin|validate_username|true|false|INSTALL_TRAEFIK"
    "TRAEFIK_DASHBOARD_PASSWORD|7_traefik|Traefik Dashboard Password|Traefik admin password (min 12 chars)|CHANGE_ME|validate_password|true|secret|INSTALL_TRAEFIK"

    # --- Section 8: Cloudflare Tunnel ---
    "INSTALL_CLOUDFLARE_TUNNEL|8_cloudflare|Install Cloudflare Tunnel?|Cloudflare Zero Trust tunnel agent|no|validate_boolean|true|false|"
    "CLOUDFLARE_TUNNEL_TOKEN|8_cloudflare|Cloudflare Tunnel Token|Cloudflare Zero Trust tunnel token|CHANGE_ME|none|false|secret|INSTALL_CLOUDFLARE_TUNNEL"
)
