# 🏢 Panduan Instalasi Frappe v15 (ERPNext + HRMS + LMS)

> Panduan ini menjelaskan cara menjalankan **Frappe Framework v15** lengkap dengan
> **ERPNext**, **HRMS**, dan **LMS** di server setupserv Anda.

---

## 📦 Komponen Yang Akan Berjalan (7 Kontainer)

| Kontainer | Fungsi |
| :--- | :--- |
| `frappe-mariadb` | Database MariaDB 11.4 khusus Frappe |
| `frappe-redis-cache` | Redis Cache (mempercepat akses halaman) |
| `frappe-redis-queue` | Redis Queue (antrian tugas latar belakang) |
| `frappe-backend` | Server Aplikasi Gunicorn (ERPNext + HRMS + LMS) |
| `frappe-websocket` | Server Realtime Socket.IO |
| `frappe-scheduler` | Penjadwal Tugas Otomatis |
| `frappe-worker-default` | Pekerja Tugas Latar Belakang |

---

## 🚀 Langkah Instalasi (Fresh / Baru)

### 1. Jalankan Stack Frappe
```bash
cd /opt/setupserv
make app-up APP=frappe
```
*(Docker akan otomatis mengunduh semua image yang dibutuhkan)*

### 2. Buat Site Baru & Install Aplikasi
Setelah semua kontainer berjalan, masuk ke kontainer backend:
```bash
docker exec -it frappe-backend bash
```

Lalu jalankan perintah-perintah berikut di dalam kontainer:
```bash
# Buat site baru (ganti erp.domainanda.com dengan domain Anda)
bench new-site erp.domainanda.com \
  --mariadb-root-password "PASSWORD_ROOT_DB_ANDA" \
  --admin-password "PasswordAdmin123!" \
  --no-mariadb-socket

# Install aplikasi
bench --site erp.domainanda.com install-app erpnext
bench --site erp.domainanda.com install-app hrms
bench --site erp.domainanda.com install-app lms

# Set sebagai default site
bench use erp.domainanda.com

# Keluar dari kontainer
exit
```

### 3. Buka di Browser
Buka `https://erp.domainanda.com` — selesai! 🎉

---

## 🔄 Langkah Restore dari Backup Lama

Jika Anda memiliki file backup Frappe sebelumnya (dari `bench backup --with-files`):

### 1. Upload File Backup ke Server
Upload 4 file backup ke folder `/tmp/hris-backup/` di server:
- `*-database.sql.gz`
- `*-files.tgz`
- `*-private-files.tgz`
- `*-site_config_backup.json`

### 2. Jalankan Stack Frappe (jika belum)
```bash
make app-up APP=frappe
```

### 3. Copy File Backup ke Kontainer
```bash
docker exec frappe-backend mkdir -p /tmp/backup
docker cp /tmp/hris-backup/. frappe-backend:/tmp/backup/
```

### 4. Buat Site & Restore
```bash
docker exec -it frappe-backend bash

# Buat site dengan nama domain sesuai backup
bench new-site hris.anterinmsi.my.id \
  --mariadb-root-password "PASSWORD_ROOT_DB_ANDA" \
  --admin-password "PasswordAdminBaru123!" \
  --no-mariadb-socket

# Restore database + files
bench --site hris.anterinmsi.my.id restore /tmp/backup/*-database.sql.gz \
  --mariadb-root-password "PASSWORD_ROOT_DB_ANDA" \
  --with-public-files /tmp/backup/*-files.tgz \
  --with-private-files /tmp/backup/*-private-files.tgz

# Install app & migrasi
bench --site hris.anterinmsi.my.id install-app erpnext
bench --site hris.anterinmsi.my.id install-app hrms
bench --site hris.anterinmsi.my.id migrate

bench use hris.anterinmsi.my.id
exit
```

### 5. Penting: Salin Encryption Key
Buka file `*-site_config_backup.json` dari backup Anda, cari nilai `"encryption_key"`,
lalu pastikan nilainya sama di file site config server baru.

---

## 🕹️ Perintah Pengelolaan

| Perintah | Fungsi |
| :--- | :--- |
| `make app-up APP=frappe` | Menyalakan / redeploy stack Frappe |
| `make app-status APP=frappe` | Cek status 7 kontainer |
| `make app-logs APP=frappe` | Lihat log semua layanan Frappe |
| `make app-down APP=frappe` | Matikan Frappe (**data aman** di persistent volume) |

## 💾 Backup Rutin
```bash
docker exec -it frappe-backend bench --site erp.domainanda.com backup --with-files
```
