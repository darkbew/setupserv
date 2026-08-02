# 🛠️ Platform Static Configurations (`configs/`)

> Folder `configs/` berisi seluruh **file konfigurasi statis** untuk kontainer platform Layer 2 (Traefik v3, Prometheus, Grafana). File-file di dalam folder ini di-mount ke dalam kontainer secara *read-only* (`:ro`).

---

## 📌 1. Fungsi Utama

Menyimpan aturan konfigurasi terpusat agar kontainer infrastruktur platform dapat berjalan dengan standar keamanan dan performa yang seragam tanpa perlu mengubah isi image kontainer.

---

## 📂 2. Struktur Folder & Konfigurasi

```text
configs/
├── traefik/
│   ├── traefik.yaml                # Konfigurasi statis Traefik v3 (entrypoints, log format, API, providers)
│   └── dynamic/
│       ├── middlewares.yaml        # Middleware dinamis (Security Headers, Gzip, Rate Limit, Basic Auth)
│       └── tls-options.yaml        # Pilihan TLS & keamanan cipher suite
├── prometheus/
│   └── prometheus.yaml             # Scrape rules & interval pengumpulan metrik Prometheus
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── datasources.yaml    # Auto-provisioning koneksi Prometheus sebagai default datasource
        └── dashboards/
            ├── dashboards.yaml     # Auto-provisioning folder dashboard Grafana
            └── default/            # File JSON dashboard bawaan (Docker, Host, Traefik)
```

---

## 🚀 3. Cara Menggunakannya

### Mengubah Security Headers / Rate Limit Traefik:
Edit file [configs/traefik/dynamic/middlewares.yaml](file:///d:/Project/setupserv/configs/traefik/dynamic/middlewares.yaml) ➔ Traefik akan otomatis mendeteksi perubahan tanpa perlu di-restart (*hot-reload*).

### Mengubah Scrape Interval Prometheus:
Edit file [configs/prometheus/prometheus.yaml](file:///d:/Project/setupserv/configs/prometheus/prometheus.yaml) ➔ Jalankan `make platform-restart`.
