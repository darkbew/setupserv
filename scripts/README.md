# 📜 Operational Management Scripts (`scripts/`)

> Folder `scripts/` berisi skrip Bash operasional yang dipanggil oleh `Makefile` untuk mengorkestrasi siklus hidup platform, verifikasi kesehatan, serta fungsi backup dan restore.

---

## 📂 Daftar Skrip Operasional

| Skrip | Perintah Makefile Terkait | Fungsi Utama |
| :--- | :--- | :--- |
| **`deploy-platform.sh`** | `make platform` | Menginisialisasi direktori data, membuat bridge network (`proxy-net`, `backend-net`, `monitoring-net`), menyusun compose overlay chain, dan menyalakan kontainer platform Layer 2. |
| **`destroy-platform.sh`** | `make platform-down` | Menghentikan dan menghapus kontainer Layer 2 platform secara aman. |
| **`status-platform.sh`** | `make platform-status` | Menampilkan matriks status healthcheck kontainer dan penggunaan resource (CPU/RAM). |
| **`logs-platform.sh`** | `make platform-logs` | Streaming log terintegrasi seluruh kontainer platform. |
| **`verify-platform.sh`** | `make verify` | Menjalankan 24 matriks pengujian independen untuk memvalidasi kesehatan Docker Engine, network isolation, routing Traefik, dan port isolation. |
| **`backup.sh`** | *(Jadwal Cron / Manual)* | Di-run di dalam kontainer `backup-worker` untuk mengarsipkan konfigurasi, mengenkripsi dengan AES-256-CBC, dan mengunggah ke Google Drive. |
| **`restore.sh`** | *(Manual)* | Di-run di dalam kontainer `backup-worker` untuk mendownload, mendekripsi, dan merestore arsip konfigurasi dari Google Drive. |

---

## 🚀 Cara Menggunakannya

Disarankan untuk selalu menggunakan perintah `make` dari root project:

```bash
make platform
make platform-status
make verify
```
