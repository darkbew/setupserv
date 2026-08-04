# Enterprise Server Infrastructure & Bootstrap Framework

> **Setupserv Infrastructure Framework** — Multi-Layer, Production-Ready, Security-Hardened Server Provisioning & Container Orchestration Engine for Ubuntu Linux & Docker Environments.

[![Bash 5.2+](https://img.shields.io/badge/Bash-5.2%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![Ubuntu Server](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20LTS-orange.svg)](https://ubuntu.com/server)
[![Docker Compose V2](https://img.shields.io/badge/Docker%20Compose-V2-blue.svg)](https://docs.docker.com/compose/)
[![Traefik v3](https://img.shields.io/badge/Traefik-v3.4-00ACD6.svg)](https://traefik.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📌 1. Dimana Tempat Menyimpan File Clone?

> [!IMPORTANT]
> **Lokasi Standar Deployment:** `/opt/setupserv`
> 
> Rekomendasi lokasi penempatan repository saat `git clone` di server Ubuntu:
> ```bash
> git clone https://github.com/darkbew/setupserv.git /opt/setupserv
> cd /opt/setupserv
> ```
> 
> **Mengapa `/opt/setupserv`?**
> - **Filesystem Hierarchy Standard (FHS):** `/opt` adalah lokasi standar Linux untuk perangkat lunak pihak ketiga yang dikelola secara terpusat.
> - **Struktur Path Relatif:** Seluruh konfigurasi Docker Compose, volume data (`data/`), log (`logs/`), backup (`backups/`), dan kunci rahasia (`secrets/`) dibuat secara otomatis **di dalam** direktori ini.
> - **Izin Akses Terisolasi:** Menghindari masalah *Permission Denied* pada volume mount Docker yang sering terjadi jika repository di-clone di dalam folder `/home/user/`.

---

## 🚀 2. Quick Start (Langsung Siap Pakai dalam 3 Langkah)

Hanya dengan **3 langkah sederhana**, server Ubuntu Anda akan terotomatisasi secara penuh (hardening keamanan OS, instalasi Docker Engine, konfigurasikan reverse proxy Traefik, monitoring, dan backup otomatis):

### Langkah 1: Clone Repository
```bash
git clone https://github.com/darkbew/setupserv.git /opt/setupserv
cd /opt/setupserv
```

### Langkah 2: Buat Konfigurasi Environment (`.env`)
Anda dapat menggunakan **Interactive Configuration Wizard**:
```bash
sudo bash bootstrap/install.sh
```
*(Jika file `.env` belum ada, wizard interaktif akan otomatis diluncurkan untuk memandu pengisian variabel).*

Atau buat file `.env` manual dari templat `.env.example`:
```bash
cp .env.example .env
nano .env
```

### Langkah 3: Jalankan Platform Infrastructure
```bash
make platform
```

🎉 **Selesai!** Seluruh 8 kontainer infrastruktur platform (Traefik, Docker Socket Proxy, Prometheus, Grafana, Node Exporter, Uptime Kuma, Dozzle, dan Backup Worker) langsung aktif dan terpantau secara *healthcheck*.

---

## 🏗️ 3. Arsitektur Infrastruktur (Multi-Layer Architecture)

Framework ini membagi infrastruktur server ke dalam 3 Layer independen dan terisolasi:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           END USERS / INTERNET                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
            ┌──────────────────────────┴──────────────────────────┐
            ▼ (Mode A: Tunnel)                                    ▼ (Mode B: Public)
┌───────────────────────────────┐                     ┌───────────────────────┐
│ Cloudflare Zero Trust Ingress │                     │ Direct Public IP      │
│ (Cloudflared Container)       │                     │ (Port 80/443 Exposed) │
└───────────────┬───────────────┘                     └───────────┬───────────┘
                │ (HTTP Port 80)                                  │ (HTTP/HTTPS)
                └──────────────────────────┬──────────────────────┘
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 2: PLATFORM INFRASTRUCTURE (Managed via `make platform`)              │
│                                                                             │
│  [ Traefik v3 Reverse Proxy ] ◄────► [ Docker Socket Proxy (API Security) ] │
│               │                                                             │
│               ├──────────────────────┬──────────────────────┐               │
│               ▼                      ▼                      ▼               │
│     [ Grafana Dashboard ]  [ Prometheus Metrics ]  [ Uptime Kuma Status ]   │
│               │                      │                      │               │
│               └──────────────────────┴──────────────────────┘               │
│               │                      │                                      │
│               ▼                      ▼                                      │
│     [ Node Exporter ]      [ Dozzle Log Viewer ]   [ Backup Worker Worker ] │
└───────────────┬─────────────────────────────────────────────────────────────┘
                │ (Bridge Network Isolation: proxy-net / backend-net)
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ LAYER 3: BUSINESS APPLICATIONS (Managed via `make app-up APP=<folder>`)     │
│                                                                             │
│  ┌───────────────────────────┐             ┌─────────────────────────────┐  │
│  │ Web Frontend App / Frappe │             │ MariaDB / PostgreSQL DB     │  │
│  │ (Connected to `proxy-net`)│────────────►│ (Strictly `backend-net`)    │  │
│  └───────────────────────────┘             └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Prinsip Keamanan Utama:
1. **Network Segmentation:**
   - **`proxy-net`**: Jaringan eksternal untuk rute HTTP reverse proxy Traefik ke kontainer frontend/web.
   - **`backend-net`**: Jaringan internal terisolasi untuk komunikasi antar-aplikasi dan database (Database **DILARANG** masuk `proxy-net`).
   - **`monitoring-net`**: Jaringan khusus pengumpulan metrik Prometheus & Dozzle.
2. **Zero Host Exposure Default:** Dalam mode default (`INGRESS_MODE=tunnel`), tidak ada port 80 atau 443 yang dibuka pada host server.
3. **Least Privilege Container Runtime:** Kontainer berjalan dengan penguncian `security_opt: ["no-new-privileges:true"]`, `cap_drop: ["ALL"]`, dan *read-only root filesystem*.

---

## 📁 4. Struktur Folder Repository

```text
/opt/setupserv/
├── .env.example                    # Templat variabel lingkungan resmi
├── .gitignore                      # Rule isolasi file sensitif & data runtime
├── Makefile                        # Antarmuka perintah operasional utama (make <target>)
├── README.md                       # Dokumentasi resmi proyek
├── CHANGELOG.md                    # Catatan versi dan perubahan
├── LICENSE                         # Lisensi lisensial MIT
│
├── bootstrap/                      # Layer 1: Ubuntu OS Hardening & Provisioning Engine
│   ├── install.sh                  # Master installer script & CLI entrypoint
│   ├── config-wizard.sh            # Orchestrator wizard interaktif
│   ├── 00-preflight.sh             # Read-only health guard OS/hardware
│   ├── 01-system-update.sh         # APT update, base packages, timezone, locale
│   ├── 02-user-setup.sh            # Pengaturan user deploy & passwordless sudoers
│   ├── 03-install-docker.sh        # Instalasi Docker Engine CE & Compose Plugin V2
│   ├── 04-install-tailscale.sh     # Setup Tailscale Mesh VPN node
│   ├── 05-security-hardening.sh    # Hardening SSH, UFW, Fail2ban, Sysctl, Journald
│   ├── 06-verify.sh                # Verifikasi independen pasca-bootstrap OS
│   ├── config/                     # Submodul wizard konfigurasi (.env generator)
│   └── lib/                        # Shared library (logging, safe file manipulators, traps)
│
├── configs/                        # Konfigurasi Statis Service Platform (Mounted Read-Only)
│   ├── traefik/                    # Configuration Traefik v3 static & dynamic middlewares
│   ├── prometheus/                 # Scrape configs & retention limits
│   └── grafana/                    # Automatic provisioning dashboards & datasources
│
├── docker/                         # Docker Compose Specifications
│   ├── platform/                   # Layer 2 Infrastructure Compose Overlays
│   │   ├── compose.yaml            # Base compose (Traefik + Docker Socket Proxy)
│   │   ├── compose.monitoring.yaml # Monitoring overlay (Prometheus, Grafana, Node Exporter, Kuma, Dozzle)
│   │   ├── compose.tunnel.yaml     # Cloudflare Tunnel agent overlay
│   │   └── compose.backup.yaml     # Automated Backup Worker overlay
│   └── apps/                       # Layer 3 Application Deployments
│       ├── README.md               # Panduan pembuatan & standar rute aplikasi Layer 3
│       └── template/               # Templat compose.yaml siap pakai (Single App & App + DB)
│
├── scripts/                        # Operational Management Scripts
│   ├── deploy-platform.sh          # Orchestrator deployment Layer 2 platform
│   ├── destroy-platform.sh         # Tear down Layer 2 platform containers
│   ├── status-platform.sh          # Matriks status & healthcheck platform
│   ├── logs-platform.sh            # Log streaming platform
│   ├── verify-platform.sh          # Matrix validator kesehatan platform
│   ├── backup.sh                   # Script eksekusi backup otomatis (di dalam container)
│   └── restore.sh                  # Script restore data & dekripsi backup
│
├── backups/                        # Tempat simpan arsip backup lokal & staging restore (git-ignored)
├── data/                           # Volume data persistent kontainer (git-ignored)
├── logs/                           # Runtime log files (git-ignored)
└── secrets/                        # Kredensial rahasia (credentials.txt) & Google Drive Service Account (git-ignored)
```

---

## 🛠️ 5. Panduan Operasional Perintah (`Makefile`)

Gunakan perintah `make` dari direktori `/opt/setupserv`:

| Perintah | Fungsi / Deskripsi |
| :--- | :--- |
| `make platform` | Menjalankan seluruh stack infrastruktur Layer 2 (Platform & Monitoring). |
| `make platform-down` | Menghentikan seluruh kontainer Layer 2 platform secara aman. |
| `make platform-restart` | Me-restart seluruh kontainer Layer 2 platform. |
| `make platform-status` | Menampilkan matriks status *healthcheck* & alokasi resource kontainer. |
| `make platform-logs` | Streaming log terintegrasi seluruh kontainer platform. |
| `make ingress-tunnel` | Mengubah mode ingress ke **Cloudflare Tunnel** (No host ports exposed). |
| `make ingress-public` | Mengubah mode ingress ke **Direct Public IP** (Port 80/443 + Let's Encrypt). |
| `make app-up APP=<folder>` | Deploy aplikasi Layer 3 dari `docker/apps/<folder>`. |
| `make app-down APP=<folder>` | Menghentikan aplikasi Layer 3 dari `docker/apps/<folder>`. |
| `make app-status APP=<folder>` | Menampilkan status kontainer aplikasi Layer 3. |
| `make app-logs APP=<folder>` | Streaming log kontainer aplikasi Layer 3. |
| `make verify` | Menjalankan pengujian independen kesehatan platform. |
| `make clean` | Membersihkan log & file runtime sementara. |

---

## 🌐 6. Dual-Mode Ingress Architecture

Platform dapat di-switch antara **dua arsitektur ingress** tanpa mengubah compose file:

### Mode A: Cloudflare Tunnel (`INGRESS_MODE=tunnel`)
- **Keunggulan:** Bebas dari serangan DDoS langsung, IP asli server tersembunyi, tidak ada port 80/443 yang dibuka di host.
- **Cara Aktivasi:**
  ```bash
  make ingress-tunnel
  ```

### Mode B: Direct Public IP (`INGRESS_MODE=public`)
- **Keunggulan:** Cocok untuk deployment bare-metal/VPS tanpa jaringan Cloudflare. Traefik otomatis mengelola sertifikat SSL Let's Encrypt ACME.
- **Cara Aktivasi:**
  ```bash
  make ingress-public
  ```

> [!NOTE]
> **Pengguna Proxmox VE / NAT VPS:**
> Jika VM Anda berada di belakang Proxmox NAT bridge (`vmbr0`), pastikan aturan *Port Forwarding* `iptables` di host Proxmox mengarahkan port 80 dan 443 ke IP VM Ubuntu Anda:
> ```bash
> iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination <IP_VM_UBUNTU>:80
> iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination <IP_VM_UBUNTU>:443
> ```

---

## 🚀 7. Menjalankan Aplikasi Layer 3 (`docker/apps/`)

### Cara Menambahkan Aplikasi Baru:

1. Buat direktori baru di dalam `docker/apps/`:
   ```bash
   mkdir -p docker/apps/my-app
   ```

2. Salin templat compose resmi:
   - **Aplikasi Tanpa Database:**
     ```bash
     cp docker/apps/template/compose.app.yaml docker/apps/my-app/compose.yaml
     ```
   - **Aplikasi Dengan Database (MariaDB/PostgreSQL):**
     ```bash
     cp docker/apps/template/compose.app-with-db.yaml docker/apps/my-app/compose.yaml
     ```

3. Edit `docker/apps/my-app/compose.yaml` (sesuaikan nama service, label subdomain, dan port internal).

4. Jalankan aplikasi:
   ```bash
   make app-up APP=my-app
   ```

---

## 🔒 8. Kredensial & Secrets Management (`secrets/`)

Seluruh file rahasia disimpan di folder `secrets/` (di-ignore oleh git, izin akses `700`):

### 🔑 Storage Kredensial Otomatis (`secrets/credentials.txt`):
Saat mengoperasikan **Interactive Configuration Wizard** (`sudo bash bootstrap/install.sh`), password acak yang di-generate secara otomatis untuk variabel berikut:
- `MARIADB_ROOT_PASSWORD` (Password root MariaDB)
- `GRAFANA_ADMIN_PASSWORD` (Password admin Grafana)
- `BACKUP_ENCRYPTION_KEY` (Kunci enkripsi backup 32 karakter)
- `TRAEFIK_DASHBOARD_PASSWORD` (Password basic auth Traefik)

akan ditampilkan di layar **SEKALI** dan secara otomatis disimpan di file `secrets/credentials.txt` dengan izin akses `600` (`-rw-------`).

### 🛡️ Autentikasi Dinamis Traefik (`configs/traefik/dynamic/auth.yaml`):
- `deploy-platform.sh` (`make platform`) secara otomatis membaca kredensial `TRAEFIK_DASHBOARD_BASIC_AUTH` dari `.env`, mengonversi format escaping (`$$` menjadi `$`), memverifikasi format hash (bcrypt `$2y$` / `$2b$` atau SHA-512 `$6$`), dan membuat file `configs/traefik/dynamic/auth.yaml` dengan izin akses `644` (`-rw-r--r--`).
- Seluruh router internal (`traefik-dashboard`, `grafana`, `kuma-admin`, `dozzle`) menggunakan middleware `traefik-auth@file` dari file provider secara aman.

### ☁️ Kebutuhan Backup Offsite (Google Drive / Rclone):
1. Buat file `secrets/gdrive-service-account.json` berisi Service Account JSON dari Google Cloud Console.
2. *(Opsional)* Buat file `secrets/rclone.conf`:
   ```ini
   [gdrive]
   type = drive
   scope = drive
   service_account_file = /secrets/gdrive-service-account.json
   ```

---

## 💾 9. Otomatisasi Backup & Restore

### Backup System (`scripts/backup.sh`)
- Menjalankan arsip konfigurasi dan dump data secara otomatis berdasarkan jadwal cron (`BACKUP_SCHEDULE`).
- Mengenkripsi file cadangan menggunakan enkripsi **AES-256-CBC** (`BACKUP_ENCRYPTION_KEY`).
- Mengunggah backup terenkripsi ke Google Drive / Remote Storage via Rclone.
- Mengatur retensi file lokal (`BACKUP_LOCAL_RETENTION_DAYS=7`).

### Restore System (`scripts/restore.sh`)
Untuk mengembalikan data dari backup remote:
```bash
# 1. Daftar backup yang tersedia di remote storage
docker exec -it backup-worker /scripts/restore.sh

# 2. Restore dari timestamp spesifik
docker exec -it backup-worker /scripts/restore.sh 2026-08-01_02-00-00 configs
```

---

## 🛡️ 10. OS Hardening Baseline (Step 05)

Modul `05-security-hardening.sh` secara otomatis mengonfigurasi:
- **SSH Hardening:** Disable root login (`PermitRootLogin no`), pembatasan percobaan login (`MaxAuthTries 3`), enforcement SSH Key.
- **UFW Firewall:** Default deny incoming policy, mengizinkan SSH port kustom & interface Tailscale.
- **Fail2ban Protection:** SSH brute-force jail otomatis dengan durasi banned 1 jam.
- **Sysctl Kernel Tuning:** Proteksi SYN Flood, anti ICMP Redirects, anti IP Spoofing.
- **Journald Log Quota:** Batas maksimum ruang simpan log 1GB.

---

## ❓ 11. Troubleshooting (FAQ)

### 1. Traefik Return 404 Not Found
- **Penyebab:** Label `traefik.enable=true` tidak terpasang atau subdomain pada `rule=Host(...)` tidak cocok dengan FQDN di `.env`.
- **Solusi:** Jalankan `make platform-status` untuk memverifikasi router aktif.

### 2. Docker Permission Denied pada Volume Mount
- **Penyebab:** UID/GID kontainer tidak memiliki akses write pada folder `data/`.
- **Solusi:** `deploy-platform.sh` me-reset izin akses data secara otomatis. Jalankan kembali `make platform-restart`.

---

## 📄 12. License

Proyek ini dilesensikan di bawah **MIT License**. Lihat file [LICENSE](LICENSE) untuk detail rincian.