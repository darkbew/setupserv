# 💾 Persistent Container Data (`data/`)

> Folder `data/` adalah direktori pusat tempat penyimpanan **data permanen (persistent volume)** dari seluruh kontainer infrastruktur platform Layer 2.

---

## ⚠️ Catatan Penting Keamanan & Performa

> [!IMPORTANT]
> **DI-IGNORE OLEH GIT (`.gitignore`):**
> Seluruh isi folder `data/` di-ignore dari Git repository agar data runtime (seperti database Prometheus, database Grafana, dan file sertifikat SSL ACME) tidak ikut ter-commit ke GitHub.

---

## 📂 Sub-Folder & Isinya

```text
data/
├── traefik/
│   └── acme.json                   # File penyimpanan sertifikat SSL Let's Encrypt (izin akses 600)
├── prometheus/
│   └── data/                       # Database deret waktu (Time-Series DB) Prometheus
├── grafana/
│   └── data/                       # Database SQLite Grafana (penyimpanan user, preference, dashboard state)
└── uptime-kuma/
    └── data/                       # Database SQLite status & riwayat uptime pemantauan
```

---

## 🔒 Izin Akses (Permissions)

Script `deploy-platform.sh` secara otomatis mengatur izin akses folder data agar kontainer non-root tidak mengalami *Permission Denied*:
- `data/traefik/acme.json` ➔ `chmod 600` (Owner read/write saja)
- `data/grafana/data` ➔ `chown 472:0` (UID Grafana)
- `data/prometheus/data` ➔ `chown 65534:65534` (UID Prometheus/nobody)
