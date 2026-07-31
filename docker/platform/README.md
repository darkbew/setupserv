# Layer 2 Platform Infrastructure Specifications

## Overview

Layer 2 provides permanent, core Docker container infrastructure services required by all applications:

1. **Docker Socket Proxy (`docker-socket-proxy`):** Read-only security firewall protecting host `/var/run/docker.sock`.
2. **Traefik v3 (`traefik`):** Edge reverse proxy, Let's Encrypt SSL termination, HTTP $\to$ HTTPS redirection, dynamic middleware library, and TLS hardening.
3. **Cloudflare Tunnel (`cloudflared`):** Zero Trust ingress gateway allowing secure public routing without open host inbound ports.
4. **Prometheus (`prometheus`):** Lightweight time-series metrics collector scraping Traefik, Node Exporter, and self-metrics.
5. **Grafana (`grafana`):** Observability dashboard auto-provisioned with Prometheus datasource and 3 default dashboards (Host System, Docker Platform, Traefik Ingress).
6. **Node Exporter (`node-exporter`):** Host hardware and OS metrics exporter (CPU, RAM, Disk, Load, Network).
7. **Uptime Kuma (`uptime-kuma`):** End-to-end HTTP/HTTPS availability monitor for Layer 3 applications.
8. **Dozzle (`dozzle`):** Zero-database, ultra-lightweight web log viewer for all container log streams via Socket Proxy.

---

## Intentionally Excluded Services & Rationale

To maintain an ultra-lightweight footprint suitable for Proxmox VE VMs (< 1.0 GB total RAM limits, ~350-450 MB actual RAM usage), the following services were intentionally excluded:

- **Loki & Promtail:** Excluded to eliminate heavy log indexing memory usage (~300 MB RAM) and constant disk I/O. Standard Docker log rotation (`DOCKER_LOG_MAX_SIZE=10m`) + Dozzle web streaming handle log management natively.
- **cAdvisor:** Excluded to prevent metric duplication (~150 MB RAM) since Proxmox VE handles hypervisor-level VM container resource stats.
- **Portainer / Watchtower:** Excluded in favor of declarative GitOps and script-driven lifecycle management (`make platform`).

---

## Memory Allocation Budget (< 1.08 GB Total Limits)

| Service | Container Name | RAM Reservation | RAM Limit | CPU Limit |
| :--- | :--- | :--- | :--- | :--- |
| **Socket Proxy** | `docker-socket-proxy` | 16 MB | 32 MB | 0.25 |
| **Traefik** | `traefik` | 32 MB | 256 MB | 0.50 |
| **Cloudflared** | `cloudflared` | 16 MB | 64 MB | 0.25 |
| **Prometheus** | `prometheus` | 64 MB | 256 MB | 0.50 |
| **Grafana** | `grafana` | 64 MB | 256 MB | 0.50 |
| **Node Exporter** | `node-exporter` | 16 MB | 32 MB | 0.25 |
| **Uptime Kuma** | `uptime-kuma` | 32 MB | 128 MB | 0.50 |
| **Dozzle** | `dozzle` | 16 MB | 64 MB | 0.25 |
| **TOTAL** | **8 Containers** | **256 MB** | **1,068 MB (1.06 GB)** | **3.00 CPUs** |

---

## Image Tag Pinning Policy

Using `:latest` image tags in production infrastructure is strictly forbidden for the following reasons:
1. **Non-Deterministic Deployments:** Running `docker compose up -d` at different times may pull different container binaries.
2. **Uncontrolled Upstream Changes:** Upstream maintainers pushing breaking changes to `:latest` can break platform deployments without notice.
3. **Rollback Failure:** Rollback operations cannot reliably return to a previous mutable `:latest` state.

All platform container specs MUST pin explicit versions (`traefik:3.4`, `tecnativa/docker-socket-proxy:0.3.0`, `prom/prometheus:v3.4.1`, `grafana/grafana:11.6.0`, `cloudflare/cloudflared:2025.7.0`, `amir20/dozzle:v8.11.8`).

---

## Repository Location & User Workflow

### Automatic Migration to `/opt/setupserv`

Selama proses bootstrap (`02-user-setup.sh`), repository secara otomatis disalin dari lokasi `git clone` awal (misalnya `/home/ubuntu/setupserv`) ke `/opt/setupserv`. Folder `/opt/setupserv` kemudian dimiliki sepenuhnya oleh user `deploy`.

### Alur Operasional Standar

```text
User Pertama (ubuntu)                    User Operasional (deploy)
─────────────────────                    ─────────────────────────
1. SSH ke server                         4. su - deploy
2. git clone <repo> setupserv            5. cd /opt/setupserv
3. sudo bash bootstrap/install.sh        6. make platform ← tanpa sudo
   ↓                                     7. make verify
   Otomatis menyalin ke /opt/setupserv   8. docker compose ps
   Otomatis set ownership deploy:deploy
```

Setelah bootstrap selesai, **seluruh operasional harian dilakukan dari user `deploy` di `/opt/setupserv`**. User pertama (`ubuntu`) tidak perlu digunakan lagi kecuali untuk maintenance OS (misalnya `apt upgrade`).

---

## Network Architecture & Isolation Rules

The platform creates three external bridge networks:

1. **`proxy-net`:** Connects Traefik reverse proxy and Cloudflared to HTTP web applications (ERPNext, Nextcloud, n8n, Gitea).
   - **RULE:** Databases (MariaDB, Redis, Postgres) MUST NEVER attach to `proxy-net`.
2. **`backend-net`:** Connects web applications to database engines and background workers.
   - **RULE:** Traefik is NOT attached to `backend-net`.
3. **`monitoring-net`:** Connects Prometheus, Grafana, Node Exporter, Uptime Kuma, and Dozzle.

---

## Application Integration Contract (Layer 3)

Layer 3 applications connect to Layer 2 infrastructure by specifying network attachment and Traefik labels in their own `compose.yaml`:

```yaml
services:
  webapp:
    image: myapp:v1.0.0
    networks:
      - proxy-net
      - backend-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
      - "traefik.http.routers.myapp.middlewares=security-headers@file"

networks:
  proxy-net:
    external: true
    name: proxy-net
  backend-net:
    external: true
    name: backend-net
```

---

## Linux Non-Root Access & Docker Group Security Policy

### Operational Non-Root Access
The framework automatically provisions the operational user `${DEPLOY_USER}` (default: `deploy`) and attaches it to the system `docker` group during host bootstrap (`bootstrap/02-user-setup.sh` & `bootstrap/03-install-docker.sh`).

### Why `docker` Group Membership is Used Instead of `sudo`
1. **CI/CD Automation & Unattended Operations:** Automated deployment pipelines (GitHub Actions, GitLab CI, Ansible) require non-interactive execution of `docker compose up -d` without requiring interactive password prompts or unconstrained root escalation.
2. **Strict Socket Permissions:** `/var/run/docker.sock` is owned by `root:docker` with mode `660` (`srw-rw----`).
3. **FORBIDDEN Security Anti-Patterns:**
   - **NEVER** run `chmod 666 /var/run/docker.sock` (violates CIS Linux Benchmark and OWASP standards by opening world-writeable socket access to unprivileged local users).
   - **NEVER** alter `docker.socket` systemd unit permissions.
   - **NEVER** expose unauthenticated TCP daemon sockets (`0.0.0.0:2375`). All external API calls MUST route through `docker-socket-proxy`.

### Session Group Token Activation
When a user is added to the `docker` group during initial bootstrap, existing active SSH sessions do not receive the new supplementary group GID immediately. To activate group membership:
- Log out and log back in to the server over SSH, **OR**
- Execute `exec su -l deploy` in the active terminal session.

---

## Disaster Recovery & Troubleshooting

1. **Certificate Renewal Reset**: If `acme.json` permissions are altered, run `chmod 600 data/traefik/acme.json` and restart Traefik (`docker compose restart traefik`).
2. **Platform Re-Verification**: Execute `make verify` or `bash scripts/verify-platform.sh` to run the assertion test matrix.

