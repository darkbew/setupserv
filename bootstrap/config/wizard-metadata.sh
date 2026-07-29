#!/usr/bin/env bash
# ==============================================================================
# Server Bootstrap Framework — Configuration Metadata Registry
# ==============================================================================
#
# Description:
#   Declarative metadata registry for all configurable environment variables.
#   Adding a new variable requires adding a single entry to CONFIG_METADATA.
#   No engine logic or UI prompt code is allowed in this file.
#
# Entry Format (10-field schema):
#   VAR_NAME|SECTION|TYPE|PROMPT|DESCRIPTION|DEFAULT|VALIDATOR|SHOW_IF|REQUIRED_IF|SECRET
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

# Declarative metadata registry table (10-field schema)
readonly CONFIG_METADATA=(
    # --- Section 1: General ---
    "HOSTNAME|1_general|hostname|Server Hostname|RFC 1123 compliant server hostname|bootstrap-server|validate_hostname|always|always|false"
    "TZ|1_general|timezone|Server Timezone|IANA format timezone (e.g. Asia/Jakarta)|Asia/Jakarta|validate_timezone|always|always|false"
    "DOMAIN|1_general|domain|Primary Domain|FQDN domain name for server services|example.com|validate_domain|always|always|false"
    "DEPLOY_USER|1_general|username|Deploy User|Non-root operational user (cannot be root)|deploy|validate_username|always|always|false"
    "SSH_PORT|1_general|port|SSH Port|SSH daemon listening port|22|validate_port|always|always|false"

    # --- Section 2: Docker ---
    "INSTALL_DOCKER|2_docker|boolean|Install Docker Engine?|Docker CE container runtime|yes|validate_boolean|always|always|false"
    "DOCKER_NETWORK_NAME|2_docker|hostname|Docker Network Name|Bridge network name for Docker services|bootstrap-net|validate_hostname|INSTALL_DOCKER=yes|INSTALL_DOCKER=yes|false"
    "DOCKER_LOG_MAX_SIZE|2_docker|text|Docker Log Max Size|Maximum container log file size|10m|validate_docker_log_size|INSTALL_DOCKER=yes|INSTALL_DOCKER=yes|false"
    "DOCKER_LOG_MAX_FILE|2_docker|integer|Docker Log Max Files|Number of rotated container log files|3|validate_positive_integer|INSTALL_DOCKER=yes|INSTALL_DOCKER=yes|false"
    "RESTART_POLICY|2_docker|text|Container Restart Policy|Default Docker restart policy|unless-stopped|validate_docker_restart|INSTALL_DOCKER=yes|INSTALL_DOCKER=yes|false"

    # --- Section 3: Security ---
    "PERMIT_ROOT_LOGIN|3_security|boolean|Permit SSH Root Login?|Disable direct SSH root authentication|no|validate_boolean|always|always|false"
    "SSH_PASSWORD_AUTH|3_security|boolean|SSH Password Auth (Phase 1)?|Allow SSH password login during initial setup|yes|validate_boolean|always|always|false"
    "ENABLE_UFW|3_security|boolean|Enable UFW Firewall?|Host UFW firewall default deny incoming|yes|validate_boolean|always|always|false"
    "ENABLE_FAIL2BAN|3_security|boolean|Enable Fail2ban?|Fail2ban SSH brute-force jail protection|yes|validate_boolean|always|always|false"

    # --- Section 4: Tailscale ---
    "INSTALL_TAILSCALE|4_tailscale|boolean|Install Tailscale Mesh VPN?|WireGuard mesh VPN node registration|yes|validate_boolean|always|always|false"
    "TAILSCALE_AUTHKEY|4_tailscale|secret|Tailscale Auth Key|Tailscale auth key (CHANGE_ME to skip)|CHANGE_ME|validate_optional|INSTALL_TAILSCALE=yes|INSTALL_TAILSCALE=yes|true"
    "TAILSCALE_HOSTNAME|4_tailscale|hostname|Tailscale Hostname|Server node name on Tailnet|bootstrap-server|validate_hostname|INSTALL_TAILSCALE=yes|INSTALL_TAILSCALE=yes|false"
    "TAILSCALE_ACCEPT_ROUTES|4_tailscale|boolean|Accept Subnet Routes?|Accept subnet routes from Tailnet|true|validate_boolean|INSTALL_TAILSCALE=yes|INSTALL_TAILSCALE=yes|false"
    "TAILSCALE_ACCEPT_DNS|4_tailscale|boolean|Accept Tailnet DNS?|Use Tailnet DNS resolution|false|validate_boolean|INSTALL_TAILSCALE=yes|INSTALL_TAILSCALE=yes|false"
    "TAILSCALE_SSH|4_tailscale|boolean|Enable Tailscale SSH?|Enable Tailscale embedded SSH server|false|validate_boolean|INSTALL_TAILSCALE=yes|INSTALL_TAILSCALE=yes|false"

    # --- Section 5: Monitoring ---
    "INSTALL_MONITORING|5_monitoring|boolean|Install Monitoring Stack?|Prometheus & Grafana monitoring suite|no|validate_boolean|always|always|false"
    "ENABLE_GRAFANA|5_monitoring|boolean|Enable Grafana?|Grafana dashboard service|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"
    "GRAFANA_ADMIN_USER|5_monitoring|username|Grafana Admin Username|Grafana dashboard admin username|admin|validate_username|ENABLE_GRAFANA=yes|ENABLE_GRAFANA=yes|false"
    "GRAFANA_ADMIN_PASSWORD|5_monitoring|password|Grafana Admin Password|Grafana admin password (min 12 chars)|CHANGE_ME|validate_password|ENABLE_GRAFANA=yes|ENABLE_GRAFANA=yes|true"
    "ENABLE_PROMETHEUS|5_monitoring|boolean|Enable Prometheus?|Prometheus metrics collector|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"
    "ENABLE_LOKI|5_monitoring|boolean|Enable Loki?|Loki log aggregation engine|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"
    "ENABLE_PROMTAIL|5_monitoring|boolean|Enable Promtail?|Promtail log collector agent|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"
    "ENABLE_NODE_EXPORTER|5_monitoring|boolean|Enable Node Exporter?|Node host metrics exporter|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"
    "ENABLE_CADVISOR|5_monitoring|boolean|Enable cAdvisor?|Container metrics exporter|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"
    "ENABLE_UPTIME_KUMA|5_monitoring|boolean|Enable Uptime Kuma?|Uptime Kuma status monitor|yes|validate_boolean|INSTALL_MONITORING=yes|INSTALL_MONITORING=yes|false"

    # --- Section 6: Backup ---
    "INSTALL_BACKUP|6_backup|boolean|Install Backup Stack?|Automated rclone backup system|no|validate_boolean|always|always|false"
    "BACKUP_SCHEDULE|6_backup|cron|Backup Schedule|Cron schedule string (e.g. 0 2 * * *)|0 2 * * *|validate_cron|INSTALL_BACKUP=yes|INSTALL_BACKUP=yes|false"
    "BACKUP_LOCAL_RETENTION_DAYS|6_backup|integer|Local Backup Retention (Days)|Local backup retention period|7|validate_positive_integer|INSTALL_BACKUP=yes|INSTALL_BACKUP=yes|false"
    "BACKUP_REMOTE_NAME|6_backup|hostname|Remote Storage Name|Rclone remote target name|gdrive|validate_hostname|INSTALL_BACKUP=yes|INSTALL_BACKUP=yes|false"
    "BACKUP_REMOTE_PATH|6_backup|text|Remote Storage Path|Remote directory path for backups|bootstrap-backups|validate_optional|INSTALL_BACKUP=yes|INSTALL_BACKUP=yes|false"
    "BACKUP_ENCRYPTION_KEY|6_backup|password|Backup Encryption Passphrase|Passphrase for backup encryption (min 12 chars)|CHANGE_ME|validate_password|INSTALL_BACKUP=yes|INSTALL_BACKUP=yes|true"

    # --- Section 7: Reverse Proxy ---
    "INSTALL_TRAEFIK|7_traefik|boolean|Install Traefik Proxy?|Traefik v3 reverse proxy|yes|validate_boolean|always|always|false"
    "ADMIN_EMAIL|7_traefik|email|Admin Email|Email for Let's Encrypt SSL notifications|admin@example.com|validate_optional|INSTALL_TRAEFIK=yes|INSTALL_TRAEFIK=yes|false"
    "SOCKET_PROXY_IMAGE_TAG|7_traefik|text|Socket Proxy Image Tag|Image tag for tecnativa/docker-socket-proxy|v0.1.1|validate_optional|INSTALL_TRAEFIK=yes|INSTALL_TRAEFIK=yes|false"
    "TRAEFIK_DASHBOARD_USER|7_traefik|username|Traefik Dashboard User|Traefik admin user|admin|validate_username|INSTALL_TRAEFIK=yes|INSTALL_TRAEFIK=yes|false"
    "TRAEFIK_DASHBOARD_PASSWORD|7_traefik|password|Traefik Dashboard Password|Traefik admin password (min 12 chars)|CHANGE_ME|validate_password|INSTALL_TRAEFIK=yes|INSTALL_TRAEFIK=yes|true"

    # --- Section 8: Cloudflare Tunnel ---
    "INSTALL_CLOUDFLARE_TUNNEL|8_cloudflare|boolean|Install Cloudflare Tunnel?|Cloudflare Zero Trust tunnel agent|no|validate_boolean|always|always|false"
    "CLOUDFLARE_TUNNEL_TOKEN|8_cloudflare|secret|Cloudflare Tunnel Token|Cloudflare Zero Trust tunnel token|CHANGE_ME|validate_optional|INSTALL_CLOUDFLARE_TUNNEL=yes|INSTALL_CLOUDFLARE_TUNNEL=yes|true"
)
