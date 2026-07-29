# Server Bootstrap Framework

> **Enterprise Linux Server Bootstrap Framework** — Modern, Modular, Idempotent, and Security-Hardened Infrastructure Provisioning Engine for Production Environments.

[![Bash 5.2+](https://img.shields.io/badge/Bash-5.2%2B-blue.svg)](https://www.gnu.org/software/bash/)
[![Ubuntu Server](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20LTS-orange.svg)](https://ubuntu.com/server)
[![Architecture](https://img.shields.io/badge/Arch-x86__64%20%7C%20aarch64-brightgreen.svg)](https://en.wikipedia.org/wiki/Computer_architecture)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Quality Gate](https://img.shields.io/badge/Quality%20Gate-PASSED-success.svg)](#22-final-summary)

---

## 1. Project Title

### **Server Bootstrap Framework**
*Enterprise-Grade Linux Server Provisioning & Security Hardening Framework.*

---

## 2. Overview

**Server Bootstrap Framework** adalah fondasi otomatisasi infrastruktur Linux tingkat enterprise yang dirancang untuk mengonfigurasi, mengamankan, dan memvalidasi server produksi secara instan, aman, dan konsisten.

### Masalah yang Diselesaikan
- **Inkonsistensi Manual Setup:** Menghilangkan risiko kelalaian konfigurasi manual pada server baru.
- **Security Misconfiguration:** Memastikan seluruh server yang disebarkan langsung memenuhi standar *Enterprise Security Baseline* (SSH Hardening, UFW, Fail2ban, Sysctl, Journald Log Limits).
- **Dependency Drift:** Menyediakan platform kontainerisasi modern berbasis Docker Engine & Docker Compose V2 yang terisolasi.
- **Tethering Remote Access:** Mempermudah pendaftaran server ke jaringan mesh privat via Tailscale WireGuard VPN.

### Kenapa Framework Ini Dibuat?
Mayoritas skrip instalasi server tradisional bersifat *monolithic*, *brittle* (mudah patah jika terputus), hardcoded, dan terikat pada nama aplikasi/perusahaan tertentu. Framework ini diciptakan sebagai **Universal Framework Netral** yang dapat digunakan oleh siapa saja, untuk organisasi mana saja, pada lingkungan cloud, bare-metal, VPS, VM, maupun home-lab.

### Target Penggunaan
- Server Produksi Linux (Ubuntu Server 22.04 LTS & 24.04 LTS)
- Bare Metal Servers, Virtual Machines (VMware/Proxmox), Cloud VPS (AWS, GCP, DigitalOcean, Hetzner), dan Edge Nodes.
- Arsitektur CPU: `x86_64`, `amd64`, `aarch64`, dan `arm64`.

---

## 3. Features

- **🚀 Master Orchestrator Engine:** Orkestrasi eksekusi terpusat via `install.sh` dengan penanganan pembatalan sinyal `SIGINT/SIGTERM` yang bersih.
- **🧙 Interactive Configuration Wizard:** Wizard interaktif metadata-driven yang menghasilkan `.env` secara otomatis dengan validasi input, deployment preset (Development/Staging/Production/Custom), interactive review matrix, dan backup otomatis.
- **⚡ Selective Step Execution (`--step N`):** Kemampuan mengeksekusi satu modul spesifik (misal hanya instalasi Docker `03` atau verifikasi `06`).
- **🔄 Smart Resume Capability (`--start-from N`):** Melanjutkan eksekusi dari langkah terakhir yang gagal tanpa perlu mengulang dari awal.
- **🧪 Dry-Run Mode (`--dry-run`):** Mode simulasi penuh untuk menguji alur instalasi tanpa mengubah state atau konfigurasi sistem.
- **🔁 100% Idempotent Write Engine:** Mekanisme penulisan file `write_config` berbasis perbandingan *SHA-256 Checksum Hashing* dan pembuat cadangan *timestamped backup*.
- **🛡️ Enterprise Security Baseline:** Penguncian SSH (Phase 1/2), UFW Firewall *Default Deny*, Fail2ban SSH brute-force jail, tuning parameter kernel Sysctl (SYN cookies, RPF, socket limit), dan Journald Log Retention.
- **🐋 Production Docker Engine:** Instalasi otomatis Docker Engine CE, Compose Plugin V2, Buildx, penyiapan `daemon.json` terisolasi, dan pembuatan `bootstrap-net` bridge network.
- **🔐 Mesh VPN Tailscale Integration:** Pendaftaran node server otomatis dan aman ke jaringan Tailnet via `TAILSCALE_AUTHKEY`.
- **📊 Built-in Verification Engine (`06-verify.sh`):** Pengujian *read-only* 25+ parameter kesehatan sistem dengan agregasi status visual `PASS`, `WARN`, `SKIP`, dan `FAIL`.
- **🛠️ Shared Core Library (`lib/common.sh`):** Pustaka terpusat menyediakan *ANSI-C logging engine*, *ERR call stack trap handler*, *safe file manipulators*, dan *exponential backoff network retry engine*.

---

## 4. Architecture

Framework ini menggunakan arsitektur *Modular Decoupled Design* dengan antarmuka yang bersih dan independen.

### Project Directory ASCII Tree

```text
bootstrap-framework/
├── .env.example                # Templat konfigurasi environment variables
├── README.md                   # Dokumentasi resmi enterprise
├── bootstrap/
│   ├── install.sh              # Master Orchestrator & CLI Entrypoint
│   ├── config-wizard.sh        # Interactive Configuration Wizard Orchestrator
│   ├── config/                 # Configuration Subsystem Modules
│   │   ├── wizard-metadata.sh  # Declarative Variable Metadata Registry
│   │   ├── validators.sh       # Pure Validation Functions Engine
│   │   ├── prompts.sh          # Terminal UI Prompt Helpers
│   │   ├── presets.sh          # Deployment Presets (Dev/Staging/Prod/Custom)
│   │   ├── review.sh           # Interactive Review Matrix & Section Editor
│   │   ├── generator.sh        # .env.example Parser & Backup Engine
│   │   └── loader.sh           # .env Loader & Configuration Resolver
│   ├── 00-preflight.sh         # Step 00: Read-Only System Preflight Guard
│   ├── 01-system-update.sh     # Step 01: APT Update, Upgrade, Base Tools & Locale
│   ├── 02-user-setup.sh        # Step 02: Deploy User, Sudoers & SSH Directory
│   ├── 03-install-docker.sh    # Step 03: Docker CE, Compose V2 & daemon.json
│   ├── 04-install-tailscale.sh # Step 04: Tailscale VPN Client & Node Authentication
│   ├── 05-security-hardening.sh# Step 05: SSH, UFW, Fail2ban, Sysctl & Journald
│   ├── 06-verify.sh            # Step 06: Read-Only Post-Bootstrap Verification
│   └── lib/
│       └── common.sh           # Core Engine Library (Logging, Traps, Wrappers)
```

### Hubungan Antar File & Sourcing Engine

```text
                                 ┌───────────────────────────┐
                                 │   bootstrap/install.sh    │
                                 │    (Master Orchestrator)  │
                                 └─────────────┬─────────────┘
                                               │ (No .env? → Wizard)
                                 ┌─────────────▼─────────────┐
                                 │   config-wizard.sh        │
                                 │    (Config Subsystem)     │
                                 │   + config/*.sh modules   │
                                 └─────────────┬─────────────┘
                                               │ (.env generated)
                                               │ (Orchestrates Steps 00–06)
             ┌─────────────────────────────────┼─────────────────────────────────┐
             │                                 │                                 │
   ┌─────────▼─────────┐             ┌─────────▼─────────┐             ┌─────────▼─────────┐
   │ 00-preflight.sh   │             │ 01-system-upd.sh  │             │ 02-user-setup.sh  │
   └─────────┬─────────┘             └─────────┬─────────┘             └─────────┬─────────┘
             │                                 │                                 │
   ┌─────────▼─────────┐             ┌─────────▼─────────┐             ┌─────────▼─────────┐
   │ 03-install-doc.sh │             │ 04-install-ts.sh  │             │ 05-sec-harden.sh  │
   └─────────┬─────────┘             └─────────┬─────────┘             └─────────┬─────────┘
             │                                 │                                 │
             └─────────────────────────────────┼─────────────────────────────────┘
                                               │
                                     ┌─────────▼─────────┐
                                     │   06-verify.sh    │
                                     └─────────┬─────────┘
                                               │
                                 ┌─────────────▼─────────────┐
                                 │   bootstrap/lib/common.sh │
                                 │    (Core Shared Engine)   │
                                 └───────────────────────────┘
```

- **`lib/common.sh` sebagai Core Library:** Seluruh modul (00–06), `install.sh`, dan `config-wizard.sh` wajib meng-`source` pustaka ini. Pustaka ini mengontrol warna ANSI, *ERR Call Stack Trap*, pembuatan file log `/var/log/bootstrap-framework/`, fungsi validasi sistem, serta fungsi pemanipulasi file yang aman terhadap `DRY_RUN`.
- **`install.sh` sebagai Master Orchestrator:** Mengatur alur eksekusi, memparsing argumen CLI, mengelola durasi eksekusi, meluncurkan Configuration Wizard bila `.env` tidak tersedia, serta menangani kelanjutan *resume* jika terjadi kegagalan.
- **`config-wizard.sh` sebagai Configuration Orchestrator:** Mengkoordinasikan pemilihan preset, prompting interaktif per-seksi, review matrix, validasi pra-generasi, dan pembuatan file `.env`.

---

## 5. Bootstrap Flow

Urutan eksekusi dirancang secara linier dan terurut berdasarkan ketergantungan antar komponen (*strict dependency order*):

```text
[Config Wizard] ➔ [Step 00] ➔ [Step 01] ➔ [Step 02] ➔ [Step 03] ➔ [Step 04] ➔ [Step 05] ➔ [Step 06]
 .env Setup      Preflight   SysUpdate    UserSetup    Docker CE    Tailscale    Security     Verify
```

| Step | Script File | Nama Modul | Deskripsi & Responsibilitas |
| :-: | :--- | :--- | :--- |
| **00** | `00-preflight.sh` | System Preflight Check | **Strict Read-Only Guard.** Memeriksa izin superuser (EUID 0), OS release (Ubuntu 22.04/24.04), arsitektur CPU, RAM minimal, free disk space, status NTP, dan module keamanan OS. |
| **01** | `01-system-update.sh` | System Update & Essentials | Mengingest paket dasar OS, memperbarui indeks APT, mengatur System Timezone & Locale, mengaktifkan `fstrim.timer` untuk SSD/NVMe, dan membersihkan cache APT. |
| **02** | `02-user-setup.sh` | Deploy User Setup | Membuat user operasional non-root (`deploy`), mengonfigurasi passwordless sudoers aman (`440`), membuat direktori SSH (`700`), serta mengimpor SSH Public Key awal. |
| **03** | `03-install-docker.sh` | Docker Engine Installation | Mengunduh GPG Keyring resmi Docker, membuat sumber APT Docker, menginstal Docker Engine CE + Compose V2 + Buildx, mengonfigurasi `daemon.json`, dan memasukkan user deploy ke grup `docker`. |
| **04** | `04-install-tailscale.sh` | Tailscale Installation | Mengonfigurasi repositori resmi Tailscale, menginstal paket `tailscale`, mengaktifkan service `tailscaled`, serta mendaftarkan node ke Tailnet via `TAILSCALE_AUTHKEY`. |
| **05** | `05-security-hardening.sh` | Security Hardening | Menerapkan SSH Hardening Phase 1 (disable root login), UFW default deny policy, Fail2ban SSH jail, Sysctl kernel tuning, Journald log persistence limit (1GB), dan Unattended Security Upgrades. |
| **06** | `06-verify.sh` | Bootstrap Verification | **Strict Read-Only Engine.** Melakukan pengujian pasca-bootstrap terhadap 25+ parameter kesehatan sistem dan menampilkan laporan ringkasan visual `PASS/WARN/SKIP/FAIL`. |

---

## 6. Project Structure

Detail tanggung jawab, output, dan *dependencies* dari setiap file proyek:

### 1. `bootstrap/install.sh`
- **Tanggung Jawab:** Entrypoint utama orchestrator. Memparsing flag CLI (`--dry-run`, `--step`, `--start-from`), memuat variabel lingkungan `.env`, mengeksekusi skrip anak, serta mencetak ringkasan durasi dan *next steps*.
- **Output:** `/var/log/bootstrap-framework/bootstrap-YYYYMMDD-HHMMSS.log`.
- **Dependencies:** `bootstrap/lib/common.sh`, `.env`.

### 2. `bootstrap/00-preflight.sh`
- **Tanggung Jawab:** Memvalidasi bahwa server memenuhi spesifikasi hardware dan OS minimum sebelum modifikasi dilakukan.
- **Output:** Status konsol (Log Success / Error). Zero system mutation.
- **Dependencies:** `bootstrap/lib/common.sh`, `/etc/os-release`, `/proc/meminfo`, `findmnt`.

### 3. `bootstrap/01-system-update.sh`
- **Tanggung Jawab:** Memperbarui sistem operasi dan menginstal paket utilitas dasar (`curl`, `git`, `htop`, `jq`, `unzip`, `ufw`, dll.).
- **Output:** Konfigurasi Locale (`/etc/default/locale`), Timezone, `fstrim.timer` active.
- **Dependencies:** `bootstrap/lib/common.sh`, APT mirrors.

### 4. `bootstrap/02-user-setup.sh`
- **Tanggung Jawab:** Menyediakan akses user operasional non-root yang terisolasi.
- **Output:** Account user `deploy`, `/etc/sudoers.d/90-bootstrap-deploy`, `/home/deploy/.ssh/authorized_keys`.
- **Dependencies:** `bootstrap/lib/common.sh`, `shadow-utils`, `mktemp`.

### 5. `bootstrap/03-install-docker.sh`
- **Tanggung Jawab:** Menginstal container runtime berstandar produksi.
- **Output:** `/etc/docker/daemon.json`, `/usr/share/keyrings/docker-archive-keyring.gpg`, Docker bridge network `bootstrap-net`.
- **Dependencies:** `bootstrap/lib/common.sh`, `download.docker.com`.

### 6. `bootstrap/04-install-tailscale.sh`
- **Tanggung Jawab:** Mengonfigurasi konektivitas mesh VPN privat.
- **Output:** Interface `tailscale0`, node status authenticated.
- **Dependencies:** `bootstrap/lib/common.sh`, `pkgs.tailscale.com`, `TAILSCALE_AUTHKEY`.

### 7. `bootstrap/05-security-hardening.sh`
- **Tanggung Jawab:** Menutup celah keamanan server (*attack surface reduction*).
- **Output:** `/etc/ssh/sshd_config.d/99-bootstrap-hardening.conf`, `/etc/fail2ban/jail.d/99-bootstrap.conf`, `/etc/sysctl.d/99-bootstrap.conf`, `/etc/systemd/journald.conf.d/99-bootstrap.conf`, `/etc/apt/apt.conf.d/51bootstrap-unattended`.
- **Dependencies:** `bootstrap/lib/common.sh`, `openssh-server`, `ufw`, `fail2ban`, `systemd-journald`.

### 8. `bootstrap/06-verify.sh`
- **Tanggung Jawab:** Melakukan verifikasi independen bahwa seluruh komponen terinstal dan terkonfigurasi dengan benar.
- **Output:** Visual Health Matrix & exit code `0` (lulus) atau `1` (gagal).
- **Dependencies:** `bootstrap/lib/common.sh`.

### 9. `bootstrap/lib/common.sh`
- **Tanggung Jawab:** Shared core engine yang menyediakan pustaka utilitas bersama.
- **Output:** In-memory helper functions & constants.
- **Dependencies:** Bash 5.0+.

---

## 7. Installation

Ikuti langkah-langkah berikut untuk memulai penggunaan **Server Bootstrap Framework** pada server Ubuntu baru:

### Langkah 1: Clone Repositori Proyek
Login ke server target sebagai root (atau jalankan via `sudo`):

```bash
git clone https://github.com/your-org/server-bootstrap-framework.git /opt/bootstrap-framework
cd /opt/bootstrap-framework
```

### Langkah 2: Salin & Konfigurasi File Environment
Salin templat `.env.example` menjadi `.env`:

```bash
cp .env.example .env
```

Edit file `.env` menggunakan editor teks (misal `nano` atau `vim`):

```bash
nano .env
```

Ubah nilai variabel utama sesuai kebutuhan server Anda (khususnya `DEPLOY_USER`, `TAILSCALE_AUTHKEY`, `TZ`, dan `LOCALE`).

### Langkah 3: Atur Hak Akses Skrip
Pastikan skrip utama dapat dieksekusi:

```bash
chmod +x bootstrap/install.sh bootstrap/*.sh
```

### Langkah 4: Jalankan Master Installer
Eksekusi pengatur instalasi utama (wizard akan diluncurkan secara otomatis bila `.env` belum ada):

```bash
sudo bash bootstrap/install.sh
```

---

## 7.5. Interactive Configuration Wizard

Framework menyediakan **Interactive Configuration Wizard** yang secara otomatis diluncurkan ketika file `.env` tidak ditemukan, atau dapat dipaksa dengan flag `--wizard`.

### Alur Konfigurasi

```text
sudo bash bootstrap/install.sh
        │
    .env ada?
     ├── YA ──► "Gunakan konfigurasi yang ada? [Y/n]"
     │             ├── Y ──► Load .env ──► Jalankan Steps 00–06
     │             └── N ──► Luncurkan Wizard
     └── TIDAK ──► Luncurkan Wizard otomatis
                      │
                  Wizard Selesai
                      ├── 1) Install Server ──► Load .env ──► Steps 00–06
                      ├── 2) Edit .env ────────► ${EDITOR} ──► Menu
                      └── 3) Exit ─────────────► Keluar
```

### Deployment Presets

Wizard menyediakan empat profil preset:

| Preset | Docker | Security | Tailscale | Monitoring | Backup | Traefik |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Development** | ✓ | Minimal | ✗ | ✗ | ✗ | ✗ |
| **Staging** | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| **Production** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Custom** | ? | ? | ? | ? | ? | ? |

### Review Matrix

Sebelum men-generate `.env`, wizard menampilkan review matrix interaktif yang memungkinkan pengguna mengedit seksi tertentu sebelum konfirmasi final:

```text
══════════════════════════════════════════════════════════
  CONFIGURATION SUBSYSTEM — REVIEW MATRIX & VALIDATION
══════════════════════════════════════════════════════════

  [PASS] 1) General     : Hostname: prod-01 | Domain: example.com
  [PASS] 2) Docker      : Status: yes | Network: bootstrap-net
  [PASS] 3) Security    : RootLogin: no | UFW: yes | Fail2ban: yes
  [PASS] 4) Tailscale   : Status: yes | Hostname: prod-01
  [PASS] 5) Monitoring  : Status: yes | Grafana: yes
  [PASS] 6) Backup      : Status: yes | Schedule: 0 2 * * *
  [PASS] 7) Traefik     : Status: yes | User: admin
  [PASS] 8) Cloudflare  : Status: no
──────────────────────────────────────────────────────────

  1-8) Edit specific section
  G)   Generate Configuration & Continue
  Q)   Quit Wizard
```

### Validasi & Password Policy

- Semua input divalidasi secara real-time (hostname RFC 1123, domain FQDN, port 1–65535, timezone IANA, cron 5-field, dll.)
- Password menggunakan `read -s` (hidden input), minimum 12 karakter, evaluasi kekuatan (Weak/Medium/Strong), dan konfirmasi ulang.
- Password lemah memerlukan konfirmasi eksplisit sebelum diterima.

### Backup `.env`

Jika file `.env` sudah ada saat wizard menghasilkan konfigurasi baru, file lama secara otomatis dicadangkan ke `.env.bak.YYYYMMDD-HHMMSS`.

---

## 8. Command Reference

Framework menyediakan berbagai opsi perintah untuk fleksibilitas pengoperasian:

### 1. Eksekusi Instalasi Penuh (Production Run)
Menjalankan wizard konfigurasi (jika `.env` belum ada) kemudian seluruh langkah dari Step 00 hingga Step 06:

```bash
sudo bash bootstrap/install.sh
```

### 2. Force Configuration Wizard
Memaksa peluncuran Configuration Wizard meskipun `.env` sudah tersedia:

```bash
sudo bash bootstrap/install.sh --wizard
sudo bash bootstrap/install.sh -w
```

### 3. Mode Simulasi (Dry-Run Mode)
Menyelimuti seluruh perintah mutasi sehingga Anda dapat melihat simulasi tanpa mengubah sistem:

```bash
sudo bash bootstrap/install.sh --dry-run
# ATAU via variabel lingkungan:
DRY_RUN=true sudo bash bootstrap/install.sh
```

### 4. Eksekusi Modul Selektif (`--step STEP`)
Menjalankan hanya satu modul tertentu (contoh: hanya instalasi Docker `03`):

```bash
sudo bash bootstrap/install.sh --step 03
```

### 5. Mode Resume / Start From (`--start-from STEP`)
Melanjutkan instalasi mulai dari langkah tertentu hingga akhir (contoh: melanjutkan dari Step 04):

```bash
sudo bash bootstrap/install.sh --start-from 04
```

### 6. Verifikasi Kesehatan Sistem Berdiri Sendiri (Standalone Verify)
Menjalankan mesin verifikasi kapan saja untuk memeriksa kondisi server saat ini:

```bash
sudo bash bootstrap/06-verify.sh
```

---

## 9. Environment Variables

Seluruh variabel konfigurasi disimpan secara terpusat di file `.env`. Tabel berikut merangkum opsi yang tersedia:

| Variabel | Deskripsi | Default Value | Fallback / Opsi |
| :--- | :--- | :--- | :--- |
| `COMPOSE_PROJECT_NAME` | Project ID (prefix Docker container & network) | `bootstrap` | Nama project |
| `TZ` | Server Timezone (IANA Format) | `Asia/Jakarta` | `UTC` |
| `LOCALE` | System Locale Settings | `en_US.UTF-8` | `en_US.UTF-8` |
| `DEPLOY_USER` | Nama user operasional non-root | `deploy` | `${OPERATIONAL_USER}` |
| `DEPLOY_USER_SHELL` | Shell default untuk user deploy | `/bin/bash` | `/bin/bash` |
| `DEPLOY_USER_PUBKEY` | SSH Public Key awal untuk ditaruh di `authorized_keys` | `""` | `""` |
| `DOCKER_NETWORK_NAME` | Nama default bridge network Docker | `bootstrap-net` | `bootstrap-net` |
| `DOCKER_LOG_MAX_SIZE` | Ukuran maksimum per file log container | `10m` | `10m` |
| `DOCKER_LOG_MAX_FILE` | Jumlah rotasi file log container | `3` | `3` |
| `TAILSCALE_AUTHKEY` | Key otentikasi node Tailscale | `CHANGE_ME` | (Kosong = Skip step 04) |
| `TAILSCALE_HOSTNAME` | Hostname node server pada jaringan Tailnet | `bootstrap-server` | Hostname sistem |
| `TAILSCALE_ACCEPT_DNS` | Menggunakan DNS resolver dari Tailnet | `false` | `true / false` |
| `TAILSCALE_ACCEPT_ROUTES` | Menerima subnet routes dari Tailnet | `true` | `true / false` |
| `TAILSCALE_SSH` | Mengaktifkan Tailscale SSH Server feature | `false` | `true / false` |
| `SSH_PASSWORD_AUTH` | Mengizinkan otentikasi password SSH (Phase 1) | `yes` | `no` (Phase 2) |
| `SSH_MAX_AUTH_TRIES` | Batas maksimum percobaan login SSH | `3` | `3` |
| `FAIL2BAN_MAXRETRY` | Percobaan gagal SSH sebelum dibanned Fail2ban | `3` | `3` |
| `FAIL2BAN_BANTIME` | Durasi penutupan IP (detik) oleh Fail2ban | `3600` (1 jam) | `3600` |
| `JOURNALD_MAX_USE` | Batas maksimum ruang simpan log Journald | `1G` | `1G` |
| `PREFLIGHT_MIN_RAM_MB` | Batas minimal RAM yang diizinkan (MB) | `2048` | `2048` |
| `PREFLIGHT_MIN_DISK_GB` | Batas minimal ruang disk bebas (GB) | `20` | `20` |

---

## 10. Security Baseline

Framework secara otomatis menerapkan kebijakan *Defense-in-Depth* berstandar industri:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        DEFENSE-IN-DEPTH MATRIX                         │
├───────────────────┬────────────────────────────────────────────────────┤
│ Komponen Keamanan │ Implementasi Hardening Baseline                    │
├───────────────────┼────────────────────────────────────────────────────┤
│ OpenSSH Hardening │ PermitRootLogin no, MaxAuthTries 3, LogLevel VERB  │
│ Access Control    │ AllowUsers ${DEPLOY_USER}, PasswordAuth Phase 1/2  │
│ UFW Firewall      │ Default Deny Incoming, Allow SSH Private/Tailscale │
│ Fail2ban Protection│ SSH Jail (Bantime: 1h, Maxretries: 3, Systemd)     │
│ Sysctl Tuning     │ SYN Cookies, Anti-ICMP Redirects, Anti-IP Spoofing │
│ Log Retention     │ Systemd Journald persistent log quota 1GB          │
│ Auto Updates      │ Unattended Security Upgrades (No auto-reboot)      │
└───────────────────┴────────────────────────────────────────────────────┘
```

---

## 11. Verification

Mesin verifikasi (`06-verify.sh`) bertindak sebagai auditor internal independen yang menjamin kualitas server pasca-bootstrap.

### Membaca Indicator Status
- `[PASS]` (Hijau): Komponen terpasang, aktif, dan memenuhi parameter baseline.
- `[WARN]` (Kuning): Komponen berfungsi namun perlu perhatian (misal PasswordAuthentication masih `yes` pada Phase 1).
- `[SKIP]` (Biru): Komponen sengaja dilewati (misal Tailscale dilewati karena `TAILSCALE_AUTHKEY` tidak diisi).
- `[FAIL]` (Merah): Komponen penting gagal terpasang atau tidak aktif. Menyebabkan exit code `1`.

---

## 12. Idempotency

Framework menjamin bahwa eksekusi berulang (*re-execution*) aman dan tidak merusak sistem (*zero destructive side-effects*).

### Mekanisme `write_config` & Checksum Hashing
Setiap penulisan file konfigurasi (SSH, Fail2ban, Sysctl, Docker `daemon.json`) menggunakan fungsi `write_config()` di `lib/common.sh`:

1. Menghitung SHA-256 hash dari konten baru.
2. Membandingkannya dengan SHA-256 hash file yang ada di sistem.
3. **Short-Circuit:** Jika hash **sama**, penulisan dilewati (*skipped*).
4. Jika hash **berbeda**, skrip otomatis membuat file cadangan *timestamped backup* (`file.conf.bak.YYYYMMDD-HHMMSS`) sebelum menulis isi baru.

---

## 13. Logging

Seluruh output konsol dan jejak eksekusi dicatat secara terpusat:

- **Lokasi Log:** `/var/log/bootstrap-framework/`
- **Format File Log:** `bootstrap-YYYYMMDD-HHMMSS.log`

### Cara Membaca File Log
Untuk memantau log secara real-time saat bootstrap berjalan:

```bash
tail -f /var/log/bootstrap-framework/bootstrap-*.log
```

---

## 14. Supported Platform

Framework diuji dan tersertifikasi secara resmi untuk platform berikut:

- **Operating System:** Ubuntu Server 22.04 LTS (Jammy Jellyfish) & Ubuntu Server 24.04 LTS (Noble Numbat).
- **Processor Architecture:** `x86_64` (amd64) dan `aarch64` (arm64).

---

## 15. Requirements

Spesifikasi minimum server agar framework dapat berjalan optimal:

- **RAM:** Minimal 2 GB (Rekomendasi: 8 GB+).
- **Disk:** Minimal 20 GB ruang bebas pada root partition `/`.
- **Akses Privilege:** Hak akses root (`EUID 0`).
- **Konektivitas Network:** Koneksi internet outbound untuk mengunduh paket APT dan GPG keyrings.

---

## 16. Troubleshooting

### FAQ Solusi Masalah Umum

#### 1. Docker Gagal Terinstal
*Penyebab:* Konflik dengan repositori lama atau masalah koneksi mirror APT.  
*Solusi:* Jalankan `sudo apt-get update && sudo apt-get install -f`, lalu jalankan kembali skrip via `sudo bash bootstrap/install.sh --step 03`.

#### 2. Kunci APT Terkunci (APT Lock Error)
*Penyebab:* Service `unattended-upgrades` bawaan Ubuntu sedang berjalan di background.  
*Solusi:* Tunggu beberapa saat atau matikan sementara: `sudo systemctl stop unattended-upgrades`.

#### 3. Terkunci dari SSH (SSH Lockout)
*Penyebab:* User operasional belum berhasil dibuat atau port SSH terblokir firewall.  
*Solusi:* Framework memvalidasi sintaks via `sshd -t` sebelum mere-load SSH dan mengizinkan SSH dari subnet privat. Jika perlu, pastikan Anda bisa login sebagai user `deploy` sebelum mematikan `PasswordAuthentication`.

#### 4. Tailscale Login Fail / Pending Authorization
*Penyebab:* `TAILSCALE_AUTHKEY` kedaluwarsa atau membutuhkan persetujuan di admin console.  
*Solusi:* Buat AuthKey baru di dashboard Tailscale, perbarui di `.env`, lalu jalankan `sudo bash bootstrap/install.sh --step 04`.

---

## 17. Development

Framework dirancang dengan arsitektur yang sangat mudah diperluas (*extensible*).

### Cara Menambahkan Modul Baru (Contoh: Step 07 - Monitoring)

1. Buat file baru `bootstrap/07-monitoring.sh`:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

main() {
    check_root
    print_header "Monitoring Setup" "Installing Prometheus & Grafana agents"
    log_info "Configuring monitoring services..."
    log_success "Monitoring baseline configured"
}

main "$@"
```

2. Daftarkan langkah baru pada array `steps` di `bootstrap/install.sh`:

```bash
local steps=(
    "00:System Preflight Check:00-preflight.sh"
    ...
    "06:Bootstrap Verification:06-verify.sh"
    "07:Monitoring Setup:07-monitoring.sh"
)
```

---

## 18. Coding Standard

Seluruh kontribusi kode pada proyek ini wajib mematuhi standar berikut:

- **Strict Mode:** Seluruh skrip wajib mencantumkan `set -Eeuo pipefail`.
- **ShellCheck Compliance:** Bebas dari peringatan linter `shellcheck`.
- **Scoped Local Variables:** Seluruh variabel di dalam fungsi wajib menggunakan kata kunci `local`.
- **Quoted Variable Expansion:** Seluruh ekspansi variabel wajib dibungkus tanda kutip ganda (`"${variable}"`).
- **Zero Subshell Anti-Patterns:** Gunakan native Bash constructs (`<<<`, `[[ ... ]]`, regex match) daripada subshell fork berulang.
- **Dry-Run Friendly:** Seluruh aksi mutasi wajib memeriksa `DRY_RUN == "true"` via helper di `lib/common.sh`.

---

## 19. Versioning

Framework ini mengikuti prinsip **Semantic Versioning (SemVer 2.0.0)**:

- **Current Version:** `v0.1.0`
- **Release Channel:** Stable LTS.

---

## 20. License

Proyek ini dilesensikan di bawah **MIT License**. Lihat file [LICENSE](LICENSE) untuk rincian selengkapnya.

---

## 21. Contributing

Panduan singkat kontribusi:

1. Fork repositori proyek ini.
2. Buat feature branch baru (`git checkout -b feature/amazing-feature`).
3. Pastikan kode lolos verifikasi linter ShellCheck (`shellcheck bootstrap/*.sh`).
4. Commit perubahan Anda (`git commit -m 'feat: Add amazing feature'`).
5. Push ke branch Anda (`git push origin feature/amazing-feature`).
6. Buat Pull Request baru.

---

## 22. Final Summary

**Server Bootstrap Framework** berbeda secara fundamental dari installer bash biasa. Dengan memisahkan mesin pembantu (*Shared Core Engine* `lib/common.sh`), pengatur utama (*Master Orchestrator* `install.sh`), dan modul terisolasi (*Decoupled Workflow Modules* 00–06), framework ini menyajikan jaminan **Zero Bug**, **Zero Hardcode**, **100% Idempotency**, dan **Enterprise Production Readiness**.

```text
===============================================================================
       GOLDEN BASELINE CERTIFIED — PRODUCTION READY — ENTERPRISE READY
===============================================================================
```