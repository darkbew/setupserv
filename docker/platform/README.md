# 🏗️ Layer 2 Infrastructure Platform (`docker/platform/`)

> Folder `docker/platform/` berisi spesifikasi Docker Compose V2 modular yang mengorkestrasi infrastruktur inti server (Reverse Proxy, Monitoring Matrix, Ingress Tunnel, dan Backup Worker).

---

## 📂 File Specification Overlays

| File Compose | Layanan / Kontainer Yang Di-run | Keterangan |
| :--- | :--- | :--- |
| **`compose.yaml`** | `traefik`, `docker-socket-proxy` | Spesifikasi dasar platform reverse proxy. |
| **`compose.monitoring.yaml`** | `prometheus`, `grafana`, `node-exporter`, `uptime-kuma`, `dozzle` | Overlay monitoring performa server, metrik, status uptime, dan streaming log. |
| **`compose.tunnel.yaml`** | `cloudflared` | Overlay agen **Cloudflare Zero Trust Tunnel** (`INGRESS_MODE=tunnel`). |
| **`compose.public.yaml`** | Bind Host Port 80 & 443 | Overlay **Direct Public IP** untuk Let's Encrypt TLS (`INGRESS_MODE=public`). |
| **`compose.backup.yaml`** | `backup-worker` | Overlay kontainer Rclone backup otomatis terenkripsi. |

---

## 🚀 Perintah Operasional Platform

Perintah dijalankan dari direktori utama `/opt/setupserv`:

```bash
make platform         # Deploy / Start seluruh layanan platform
make platform-restart # Restart seluruh layanan platform
make platform-status  # Cek status kesehatan 8 kontainer platform
make platform-logs    # Streaming log terintegrasi
make platform-down    # Menghentikan seluruh kontainer platform
```
