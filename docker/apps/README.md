# 🚀 Panduan Deployment Aplikasi (Layer 3) — Untuk Pemula

> Dokumentasi ini dibuat khusus agar orang awam dapat dengan mudah menambahkan, mengelola, dan menjalankan berbagai aplikasi web (seperti **Dolibarr, WordPress, Nextcloud, N8N, Frappe/ERPNext, Gitea, dll**) di server ini hanya dalam beberapa langkah sederhana.

---

## 📌 1. Apa Fungsi Folder `docker/apps/` Ini?

Bayangkan folder `docker/apps/` ini sebagai **"Garasi Aplikasi"**:
- Setiap aplikasi bisnis yang ingin Anda jalankan akan memiliki **satu folder tersendiri** di dalam `docker/apps/`.
- Contoh:
  - Dolibarr ➔ `/opt/setupserv/docker/apps/dolibarr/compose.yaml`
  - WordPress ➔ `/opt/setupserv/docker/apps/wordpress/compose.yaml`
  - N8N ➔ `/opt/setupserv/docker/apps/n8n/compose.yaml`

---

## 💡 2. Aturan Emas & Konsep Dasar (Sangat Sederhana)

1. **Tidak Perlu Buka Port di Server (`ports:` Tidak Diperlukan)**
   Anda **tidak perlu** repot-repot membuka port (seperti port 8080, 3000, 8000) ke publik. Reverse proxy **Traefik** akan secara otomatis mendeteksi aplikasi Anda dan menghubungkannya ke subdomain yang Anda tentukan (misal: `erp.domainanda.com`).

2. **Database Aman Tersembunyi (`backend-net`)**
   Jika aplikasi Anda menggunakan database (MariaDB, PostgreSQL, MySQL, Redis), database tersebut akan otomatis disembunyikan di jaringan privat internal (`backend-net`). Orang luar di internet **tidak bisa mengakses database secara langsung**, sehingga sangat aman dari hacker.

3. **Cukup 1 Perintah untuk Menyalakan**
   Anda tidak perlu menghafal perintah Docker yang panjang. Cukup jalankan perintah singkat: `make app-up APP=<nama-folder-aplikasi>`.

---

## 🌐 2.5 Diagram Alur Jaringan & Routing Aplikasi

Berikut adalah gambaran visual bagaimana lalu lintas data dari pengguna di internet masuk ke aplikasi dan database Anda secara aman:

```text
[ Pengguna di Internet / End Users ]
                 │
                 ▼ (HTTPS Enkripsi - Diselesaikan di Cloudflare Edge)
┌─────────────────────────────────────────────────────────────┐
│ Cloudflare Zero Trust Ingress Gateway                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ (Tunnel Terenkripsi)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Server Host (/opt/setupserv)                                │
│                                                             │
│  [ Kontainer cloudflared ]                                  │
│           │                                                 │
│           ▼ (HTTP Port 80 Internal)                         │
│  [ Traefik v3 Reverse Proxy ]                               │
│           │                                                 │
│           ├─────────────────────────┐                       │
│           │ (Internal proxy-net)    │ (Internal proxy-net)  │
│           ▼                         ▼                       │
│  ┌─────────────────┐       ┌─────────────────┐              │
│  │ Single App      │       │ Web Frontend App│              │
│  │ (misal: N8N)    │       │ (misal:Dolibarr)│              │
│  └─────────────────┘       └────────┬────────┘              │
│                                     │ (Internal backend-net)│
│                                     ▼                       │
│                            ┌─────────────────┐              │
│                            │ Database Engine │              │
│                            │ (PostgreSQL /   │              │
│                            │  MariaDB)       │              │
│                            └─────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🛠️ 3. Panduan 4 Langkah Menambah Aplikasi Baru

### Langkah 1: Buat Folder Aplikasi Baru
Masuk ke terminal server Anda, lalu buat folder baru untuk aplikasi Anda (contoh nama aplikasi: `kasir`):

```bash
mkdir -p /opt/setupserv/docker/apps/kasir
```

### Langkah 2: Salin File Templat Konfigurasi
Kami telah menyediakan templat siap pakai di folder `template/`:

- **Pilihan A: Jika aplikasi TIDAK butuh database** (contoh: website statis, N8N dengan SQLite):
  ```bash
  cp /opt/setupserv/docker/apps/template/compose.app.yaml /opt/setupserv/docker/apps/kasir/compose.yaml
  ```

- **Pilihan B: Jika aplikasi BUTUH database** (contoh: WordPress, Dolibarr, ERPNext):
  ```bash
  cp /opt/setupserv/docker/apps/template/compose.app-with-db.yaml /opt/setupserv/docker/apps/kasir/compose.yaml
  ```

### Langkah 3: Edit Konfigurasi Aplikasi
Buka dan edit file `compose.yaml` yang baru saja disalin:

```bash
nano /opt/setupserv/docker/apps/kasir/compose.yaml
```

**Hal penting yang perlu Anda ubah di dalam file:**
1. **`APP_SUBDOMAIN`**: Nama subdomain yang ingin Anda gunakan (contoh: `kasir` untuk akses `kasir.domainanda.com`).
2. **`loadbalancer.server.port`**: Port internal aplikasi (contoh: `80` untuk WordPress, `8080` untuk Dolibarr).
3. **Password Database**: Ganti `CHANGE_ME` dengan password kuat pilihan Anda.

*(Tekan `Ctrl + O` lalu `Enter` untuk menyimpan, lalu `Ctrl + X` untuk keluar dari nano).*

### Langkah 4: Jalankan Aplikasi!
Jalankan perintah berikut dari direktori `/opt/setupserv`:

```bash
make app-up APP=kasir
```

🎉 **Selamat!** Aplikasi Anda langsung berjalan di background dan otomatis terhubung ke internet via Traefik.

---

## 🕹️ 4. Perintah Praktis Pengelolaan Aplikasi

Seluruh pengelolaan aplikasi menggunakan perintah `make` dari folder `/opt/setupserv`:

| Perintah | Contoh Penggunaan | Fungsi / Penjelasan |
| :--- | :--- | :--- |
| **Menyalakan Aplikasi** | `make app-up APP=kasir` | Menyalakan aplikasi (atau menerapkan perubahan jika file compose di-edit). |
| **Mengecek Status** | `make app-status APP=kasir` | Mengecek apakah aplikasi sedang berjalan, sehat (healthy), atau error. |
| **Melihat Log / Error** | `make app-logs APP=kasir` | Melihat pesan log aplikasi secara *real-time* (sangat berguna jika aplikasi tidak bisa dibuka). |
| **Mematikan Aplikasi** | `make app-down APP=kasir` | Mematikan aplikasi. **Data Anda aman!** Data simpanan tidak akan hilang. |

---

## ❓ 5. Troubleshooting (Masalah Yang Sering Dialami Pemula)

### 1. Halaman Web Menampilkan `404 Not Found` dari Traefik
- **Penyebab:** Subdomain belum diatur dengan benar di DNS Cloudflare / `.env`, atau label Traefik di `compose.yaml` salah ketik.
- **Solusi:** 
  1. Pastikan subdomain (misal `kasir.domainanda.com`) sudah di-point ke Cloudflare Tunnel / IP Server.
  2. Cek apakah label `traefik.enable=true` sudah ada di file `compose.yaml` aplikasi.

### 2. Halaman Web Menampilkan `502 Bad Gateway`
- **Penyebab:** Traefik berhasil menerima permintaan, tetapi aplikasi Anda belum selesai booting atau port internal aplikasi salah.
- **Solusi:**
  1. Tunggu 10–30 detik (beberapa aplikasi butuh waktu booting awal untuk membuat tabel database).
  2. Pastikan port pada `traefik.http.services.<nama>.loadbalancer.server.port` sesuai dengan port internal aplikasi.
  3. Cek log dengan perintah: `make app-logs APP=<nama-app>`.

### 3. Apakah Data Saya Hilang Jika Aplikasi Di-stop (`make app-down`)?
- **Jawab: TIDAK.** Seluruh data database dan file unggahan disimpan secara permanen di direktori persistent (`/opt/setupserv/data/` atau Docker Volume). Menjalankan `make app-down` hanya menghentikan kontainer, data Anda tetap utuh.
