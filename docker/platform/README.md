# Layer 2 Platform Infrastructure Specifications

## Overview

Layer 2 provides core Docker container infrastructure services required by all applications:

- **Traefik v3 (`traefik`):** Edge reverse proxy, automatic Let's Encrypt TLS termination, HTTP $\to$ HTTPS redirection.
- **Docker Socket Proxy (`docker-socket-proxy`):** Read-only security proxy protecting host `/var/run/docker.sock`.

---

## Configuration Variables & Tag Pinning Policy

### Key Environment Variables
- `ADMIN_EMAIL`: Email address for Let's Encrypt SSL registration and certificate renewal notifications. If unset or placeholder, `deploy-platform.sh` falls back dynamically to `admin@${DOMAIN}`.
- `SOCKET_PROXY_IMAGE_TAG`: Pinned version tag for `tecnativa/docker-socket-proxy` (default: `v0.1.1`).

### Image Tag Pinning Policy (Why `:latest` is Forbidden)
Using `:latest` image tags in production infrastructure is strictly forbidden for the following security and operational reasons:
1. **Non-Deterministic Deployments:** Running `docker compose up -d` on two nodes at different times may pull different container binaries.
2. **Uncontrolled Upstream Changes:** Upstream maintainers pushing breaking changes to `:latest` will break platform deployments without notice.
3. **Rollback Failure:** Rollback operations cannot reliably return to a previous `:latest` state since the tag is mutable.

All platform container specs MUST pin explicit major.minor versions (`traefik:v3.4`, `tecnativa/docker-socket-proxy:v0.1.1`).

---

## Pre-Flight Port Conflict Detection

`scripts/deploy-platform.sh` inspects host network ports before running `docker compose up -d`:
- Verifies host TCP **port 80** and **port 443** are free.
- If a port is bound by an non-platform process (e.g. standalone Nginx or Apache), `deploy-platform.sh` aborts execution with an explicit error:
  ```text
  [ERROR] Port 80 already used by nginx (PID 1234)
  [ERROR] Resolve the conflict before deploying Layer 2.
  ```
- Exits with exit code `1` until port conflicts are resolved by the operator.

---

## Network Architecture & Isolation Rules

The platform creates three external bridge networks:

1. **`proxy-net`:** Connects Traefik reverse proxy to HTTP web applications (ERPNext, MinIO, Gitea).
   - **RULE:** Databases (MariaDB, Redis, Postgres) MUST NEVER attach to `proxy-net`.
2. **`backend-net`:** Connects web applications to database engines and background workers.
   - **RULE:** Traefik is NOT attached to `backend-net`.
3. **`monitoring-net`:** Connects Prometheus, Promtail, and Node Exporter.

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

networks:
  proxy-net:
    external: true
    name: proxy-net
  backend-net:
    external: true
    name: backend-net
```

---

## Security Compliance Rules

1. **No Host Sockets:** Applications must NEVER mount `/var/run/docker.sock`.
2. **No Direct Ingress:** Applications must NEVER expose host ports 80 or 443.
3. **No Root Users:** Applications should run as non-root users (`user: "1000:1000"`).
4. **Security Options:** Applications must specify `no-new-privileges:true` and `cap_drop: [ALL]`.
