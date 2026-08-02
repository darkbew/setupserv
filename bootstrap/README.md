# ⚙️ Bootstrap Engine (Layer 1: Host OS Hardening & Provisioning)

> Folder `bootstrap/` berisi seluruh skrip otomatisasi tingkat sistem operasi (Ubuntu Server 22.04 / 24.04 LTS) untuk hardening keamanan, instalasi Docker Engine V2, setup Tailscale Mesh VPN, dan konfigurasi lingkungan.

---

## 📌 1. Fungsi Utama Modul Bootstrap

Modul ini bertanggung jawab untuk mengubah server Ubuntu Server polosan menjadi **Server Standar Keamanan Enterprise** sebelum kontainer Docker dijalankan.

---

## 📂 2. Struktur Modul & Skrip

| File / Modul | Fungsi & Penjelasan |
| :--- | :--- |
| **`install.sh`** | **Master Installer Script.** Titik masuk utama untuk menjalankan seluruh rangkaian bootstrap OS. |
| **`config-wizard.sh`** | **Interactive Configuration Wizard.** Memandu operator mengisi file `.env` secara interaktif. |
| **`00-preflight.sh`** | Pemeriksaan awal (*read-only healthcheck*): mengecek RAM, CPU, disk space, OS, dan hak akses root. |
| **`01-system-update.sh`** | Melakukan `apt update`, penginstalan paket dasar (curl, git, ufw, jq), timezone, dan locale. |
| **`02-user-setup.sh`** | Membuat user deployer non-root (`deploy`) dengan akses sudoers terisolasi. |
| **`03-install-docker.sh`** | Menginstal **Docker Engine CE** resmi dan plugin **Docker Compose V2** terbaru. |
| **`04-install-tailscale.sh`** | *(Opsional)* Menginstal dan mengonfigurasi **Tailscale Mesh VPN** untuk akses server jarak jauh yang aman. |
| **`05-security-hardening.sh`** | Hardening keamanan OS: SSH (`PermitRootLogin no`), UFW Firewall, Fail2ban, Sysctl kernel tuning, & limit log journald. |
| **`06-verify.sh`** | Pengujian verifikasi akhir pasca-bootstrap OS untuk memastikan seluruh konfigurasi telah aktif. |

---

## 🚀 3. Cara Menggunakannya

### Jalankan Master Installer (Instalasi Otomatis):
```bash
sudo bash bootstrap/install.sh
```

*Skrip akan secara otomatis menjalankan seluruh tahapan dari `00-preflight.sh` hingga `06-verify.sh`.*
