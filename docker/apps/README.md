# Layer 3 Application Infrastructure & Deployment Specifications

## Overview

Direktori `docker/apps/` adalah tempat penyimpanan spesifikasi terisolasi untuk seluruh aplikasi Layer 3 (seperti ERPNext, Nextcloud, N8N, Gitea, Custom Web Applications, API Services). 

Seluruh aplikasi di dalam arsitektur ini tunduk pada prinsip **Zero Host Exposure**, **Strict Network Segmentation**, dan **Declarative GitOps Management**.

---

## Architecture & Routing Model

Lalu lintas data pada Layer 3 mengalir secara terenkripsi dan terenkapsulasi melalui arsitektur berikut:

```text
[ Internet / End Users ]
           │
           ▼ (HTTPS / TLS 1.3 - Terminated at Cloudflare Edge)
┌─────────────────────────────────────────────────────────────┐
│ Cloudflare Zero Trust Ingress Gateway                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ (Encrypted Tunnel WireGuard/QUIC)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Host Server (Internal Bridge Networks)                      │
│                                                             │
│  [ cloudflared container ]                                  │
│           │                                                 │
│           ▼ (HTTP Port 80 internal)                         │
│  [ Traefik v3 Reverse Proxy ]                               │
│           │                                                 │
│           ├─────────────────────────┐                       │
│           │ (proxy-net)             │ (proxy-net)           │
│           ▼                         ▼                       │
│  ┌─────────────────┐       ┌─────────────────┐              │
│  │ App Single      │       │ App Web (Front) │              │
│  │ Container       │       └────────┬────────┘              │
│  └─────────────────┘                │ (backend-net)         │
│                                     ▼                       │
│                            ┌─────────────────┐              │
│                            │ Database Engine │              │
│                            │ (PostgreSQL/    │              │
│                            │  MariaDB)       │              │
│                            └─────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

### Key Routing Rules:
1. **Tidak Ada Host Port Published (`ports:` DILARANG):** Tidak ada kontainer aplikasi yang membuka port `80`, `443`, `5432`, `3306`, dll. secara langsung ke IP publik/host server.
2. **Internal HTTP Routing:** Cloudflare Edge mengakhiri enkripsi SSL/TLS publik. Traffic diteruskan dari `cloudflared` ke Traefik v3 via HTTP port 80 pada entrypoint `web`.
3. **Service Discovery via Traefik Labels:** Traefik membaca konfigurasi rute aplikasi secara dinamis melalui `labels` yang terdefinisi pada kontainer web frontend.

---

## Network Isolation Contract

Arsitektur platform menyediakan dua jaringan eksternal terpisah (*external bridge networks*):

| Nama Network | Tipe | Aksesibilitas | Kontainer yang Boleh Join |
|---|---|---|---|
| **`proxy-net`** | External Bridge | Di-scan oleh Traefik Ingress | Traefik, Cloudflared, Web Frontend Application |
| **`backend-net`** | External Bridge | Terisolasi dari Traefik & Internet | Web Frontend Application, Database Engine, Cache, Worker |

### ⚠️ PERATURAN MUTLAK SECURITY NETWORK:
- **DATABASE ENGINE (PostgreSQL, MariaDB, Redis, MongoDB) DILARANG KERAS BERADA DI `proxy-net`!**
- Database hanya boleh bergabung ke `backend-net`.
- Hanya kontainer aplikasi/web frontend yang diizinkan memiliki dua interface (`proxy-net` dan `backend-net`).

---

## Standar Label Traefik v3

Kontainer web/frontend wajib menyertakan set label Traefik berikut pada `compose.yaml`:

```yaml
labels:
  # 1. Aktifkan Service Discovery Traefik
  - "traefik.enable=true"
  
  # 2. Atur Routing Rule berdasarkan FQDN Domain/Subdomain
  - "traefik.http.routers.<app-name>.rule=Host(`${APP_SUBDOMAIN}.${DOMAIN}`)"
  
  # 3. Tetapkan Entrypoint (Wajib: web)
  - "traefik.http.routers.<app-name>.entrypoints=web"
  
  # 4. Tentukan Port Internal Kontainer (Port mana tempat aplikasi mendengarkan)
  - "traefik.http.services.<app-name>.loadbalancer.server.port=8080"
  
  # 5. Pasang Middleware Keamanan Enterprise Standard
  - "traefik.http.routers.<app-name>.middlewares=security-headers@file,rate-limit@file"
```

---

## Alur Pembuatan Project Aplikasi Baru

### 1. Buat Direktori Aplikasi
Buat direktori baru di dalam `docker/apps/`:
```bash
mkdir -p docker/apps/my-app
```

### 2. Salin Template Compose
Gunakan salah satu template resmi yang tersedia:
- Untuk aplikasi tanpa database:
  ```bash
  cp docker/apps/template/compose.app.yaml docker/apps/my-app/compose.yaml
  ```
- Untuk aplikasi dengan database (PostgreSQL/MariaDB):
  ```bash
  cp docker/apps/template/compose.app-with-db.yaml docker/apps/my-app/compose.yaml
  ```

### 3. Sesuaikan Konfigurasi
Edit `docker/apps/my-app/compose.yaml` untuk me-rename nama service, subdomain (`APP_SUBDOMAIN`), port internal kontainer, serta environment variable pendukung.

---

## Panduan Operasional Management (Makefile Interface)

Semua perintah deployment aplikasi dijalankan melalui `Makefile` di root proyek:

### 1. Deploy / Start Aplikasi (`make app-up`)
```bash
make app-up APP=my-app
```
*Perintah ini akan memvalidasi keberadaan `docker/apps/my-app/compose.yaml` dan menjalankannya secara background (`up -d`).*

### 2. Cek Status Aplikasi (`make app-status`)
```bash
make app-status APP=my-app
```
*Menampilkan matriks kontainer, status healthcheck, dan alokasi resource.*

### 3. Tail Logs Aplikasi (`make app-logs`)
```bash
make app-logs APP=my-app
```
*Menampilkan streaming log langsung dari seluruh kontainer dalam grup aplikasi.*

### 4. Stop / Tear Down Aplikasi (`make app-down`)
```bash
make app-down APP=my-app
```
*Menghentikan dan menghapus kontainer aplikasi dengan aman tanpa menghapus volume data persistent.*

---

## Panduan Update & Rollback Aplikasi

### Alur Update Aplikasi (Zero Downtime / Rolling Upgrade)
1. Perbarui nilai tag versi image pada `compose.yaml` (misal dari `v1.1.0` ke `v1.2.0`).
2. Jalankan pembaruan deployment:
   ```bash
   make app-up APP=my-app
   ```
3. Docker Compose akan mengunduh image baru, menghentikan kontainer lama, dan menyalakan kontainer baru tanpa mengganggu kontainer lain.

### Alur Rollback Aplikasi
1. Kembalikan tag image pada `compose.yaml` ke versi stabil sebelumnya.
2. Jalankan perintah redeploy:
   ```bash
   make app-up APP=my-app
   ```
3. Jika terdapat perubahan schema database, lakukan restore snapshot database sebelum aplikasi di-start ulang.

---

## Security Best Practices

1. **Pinned Image Tags:** Selalu gunakan versi spesifik (misal `postgres:16.3-alpine`), **DILARANG** menggunakan tag `:latest` di lingkungan produksi.
2. **Least Privilege Container User:** Gunakan `user: "1000:1000"` atau `user: "65534:65534"` jika kontainer mendukung *non-root mode*.
3. **Hardening Attributes:** Sertakan `security_opt: ["no-new-privileges:true"]`, `cap_drop: ["ALL"]`, dan `read_only: true` (dengan `tmpfs` untuk lokasi writable sementara).
4. **Explicit Resource Limits:** Tetapkan batas maksimal `cpus` dan `memory` pada seksi `deploy.resources.limits` untuk mencegah starvation OOM pada server.

---

## Troubleshooting Umum

### 1. HTTP 404 Not Found dari Traefik
- **Penyebab:** Label `traefik.enable=true` tidak ada, atau Host rule subdomain tidak sesuai dengan domain di `.env`.
- **Solusi:** Periksa `make app-logs APP=my-app` dan jalankan `make platform-status` untuk memastikan router terdaftar.

### 2. HTTP 502 Bad Gateway dari Traefik
- **Penyebab:** Traefik tidak dapat menghubungkan port internal aplikasi, atau aplikasi belum selesai booting.
- **Solusi:**
  1. Pastikan port pada `loadbalancer.server.port` sama dengan port internal aplikasi.
  2. Pastikan kontainer terhubung ke `proxy-net`.
  3. Cek log aplikasi: `make app-logs APP=my-app`.

### 3. Application Cannot Connect to Database (Connection Refused / Timeout)
- **Penyebab:** Kontainer database tidak berada pada `backend-net`, atau hostname database pada environment variable aplikasi salah.
- **Solusi:** Gunakan nama service kontainer database (misal `postgres-db`) sebagai hostname koneksi database pada `backend-net`.

### 4. Permission Denied pada Persistent Volume
- **Penyebab:** UID/GID pengguna di dalam kontainer tidak memiliki akses write ke lokasi mount volume host.
- **Solusi:** Atur kepemilikan direktori host sebelum deployment menggunakan `chown -R <UID>:<GID> data/<app-name>`.
