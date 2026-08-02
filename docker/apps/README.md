# 🚀 Panduan Deployment Aplikasi (Layer 3) — Untuk Pemula

> Dokumentasi ini dibuat khusus agar siapa pun (termasuk orang awam) dapat dengan mudah menambahkan, mengonfigurasi, dan mengelola aplikasi web apa pun (**seperti Frappe, Dolibarr, WordPress, Nextcloud, N8N, Odoo, GitLab, Supabase, dll**) di server ini.

---

## 📌 1. Konsep Dasar "Garasi Aplikasi" (`docker/apps/`)

Folder `docker/apps/` adalah tempat penyimpanan seluruh aplikasi bisnis yang akan Anda jalankan.

Setiap aplikasi bisnis akan memiliki **satu folder tersendiri** di dalam `docker/apps/`:
- Contoh Frappe ➔ `/opt/setupserv/docker/apps/frappe/compose.yaml`
- Contoh WordPress ➔ `/opt/setupserv/docker/apps/wordpress/compose.yaml`
- Contoh Nextcloud ➔ `/opt/setupserv/docker/apps/nextcloud/compose.yaml`

---

## 💡 2. Aturan Emas Deployment Aplikasi

1. **JANGAN Membuka Port Host (`ports:` DILARANG):**
   Anda **tidak perlu** repot-repot membuka port (seperti port 8080, 3000, 8000) ke publik. Reverse proxy **Traefik** akan secara otomatis mendeteksi aplikasi Anda dan menghubungkannya ke domain/subdomain yang Anda tentukan (misal: `erp.domainanda.com`).

2. **Gunakan Jaringan Bridges Yang Tepat:**
   - **`proxy-net`**: Digunakan oleh service web/frontend aplikasi agar dapat dijangkau oleh Traefik.
   - **`backend-net`**: Digunakan oleh service database (MariaDB, PostgreSQL, Redis) agar **terisolasi aman dari internet**.

3. **Gunakan Templat Yang Sudah Disediakan:**
   Folder `docker/apps/template/` sudah menyediakan templat siap pakai untuk aplikasi tanpa database (`compose.app.yaml`) maupun aplikasi dengan database (`compose.app-with-db.yaml`).

---

## 🛠️ 3. Langkah-Langkah Menambahkan Aplikasi Baru

### Langkah 1: Buat Folder Aplikasi Baru
Buat folder dengan nama aplikasi Anda di bawah `docker/apps/`:
```bash
mkdir -p docker/apps/nama-aplikasi
```
*(Contoh: `mkdir -p docker/apps/wordpress`)*

---

### Langkah 2: Buat File `compose.yaml`
Buat file `docker/apps/nama-aplikasi/compose.yaml` dengan struktur standar berikut:

```yaml
name: nama-aplikasi-app

networks:
  proxy-net:
    external: true
    name: proxy-net
  backend-net:
    external: true
    name: backend-net

services:
  # Service Web App / Frontend
  app:
    image: nama-image:v1.0.0
    container_name: app-nama-aplikasi
    restart: unless-stopped
    environment:
      - DB_HOST=db
    networks:
      - proxy-net
      - backend-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nama-aplikasi.rule=Host(`subdomain.${DOMAIN:-example.com}`)"
      - "traefik.http.routers.nama-aplikasi.entrypoints=${APP_ENTRYPOINT:-web}"
      - "traefik.http.services.nama-aplikasi.loadbalancer.server.port=80"
      - "traefik.http.routers.nama-aplikasi.middlewares=security-headers@file,gzip-compress@file"

  # Service Database Engine (Terisolasi di backend-net)
  db:
    image: mariadb:11.4
    container_name: db-nama-aplikasi
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-CHANGE_ME}
    networks:
      - backend-net
```

---

### Langkah 3: Menyalakan Aplikasi
Gunakan perintah sederhana Makefile:

```bash
# 1. Jalankan aplikasi
make app-up APP=nama-aplikasi

# 2. Cek status kesehatan kontainer
make app-status APP=nama-aplikasi

# 3. Lihat log streaming kontainer
make app-logs APP=nama-aplikasi

# 4. Mematikan aplikasi
make app-down APP=nama-aplikasi
```

---

## 🕹️ 4. Ringkasan Perintah Pengelolaan Aplikasi

| Perintah | Fungsi |
| :--- | :--- |
| `make app-up APP=<folder>` | Menyalakan / deploy aplikasi |
| `make app-status APP=<folder>` | Cek status kontainer aplikasi |
| `make app-logs APP=<folder>` | Streaming log kontainer aplikasi |
| `make app-down APP=<folder>` | Menghentikan aplikasi (**data aman** di persistent volume) |
