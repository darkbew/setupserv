# 🐳 Docker Compose Architecture (`docker/`)

> Folder `docker/` berisi seluruh spesifikasi **Docker Compose V2** yang mengorkestrasi layanan infrastruktur platform (Layer 2) dan aplikasi bisnis (Layer 3).

---

## 📂 Struktur Pembagian Layer

```text
docker/
├── platform/      # LAYER 2: Platform Infrastructure Overlays (Traefik, Socket Proxy, Prometheus, Grafana, dll)
└── apps/          # LAYER 3: Business Applications (Frappe, Dolibarr, WordPress, N8N, dll)
```

---

## 📌 Penjelasan Sub-Folder

1. **`docker/platform/` (Layer 2)**:
   - Dikelola terpusat menggunakan perintah: `make platform`
   - Berisi komponen dasar reverse proxy, monitoring, cloudflare tunnel, dan backup worker.
   - Lihat panduan lengkap di: [docker/platform/README.md](file:///d:/Project/setupserv/docker/platform/README.md)

2. **`docker/apps/` (Layer 3)**:
   - Dikelola per-aplikasi menggunakan perintah: `make app-up APP=<nama-app>`
   - Tempat menyimpan file spesifikasi kontainer aplikasi bisnis.
   - Lihat panduan lengkap di: [docker/apps/README.md](file:///d:/Project/setupserv/docker/apps/README.md)
