# 🏢 Panduan Deployment & Restore Frappe v15 (ERPNext + HRMS)

> Panduan ini menjelaskan cara mengelola dan menjalankan **Frappe Framework v15** berbasis arsitektur resmi **`frappe_docker`** yang diadaptasi secara sempurna ke platform setupserv Anda (menggunakan Traefik, `proxy-net`, `backend-net`, dan otomatisasi `configurator`).

---

## 📦 Komponen Layanan (9 Kontainer Terkoordinasi)

| Kontainer | Fungsi / Peran |
| :--- | :--- |
| `frappe-mariadb` | Database MariaDB 11.4 khusus Frappe |
| `frappe-redis-cache` | Redis Cache (mempercepat akses halaman) |
| `frappe-redis-queue` | Redis Queue (antrian tugas latar belakang) |
| `frappe-configurator` | Inisialisasi otomatis `common_site_config.json` (*One-shot container*) |
| `frappe-backend` | Server Aplikasi Gunicorn Python (`backend:8000`) |
| `frappe-frontend` | Nginx Web Server & Static Assets (`frontend:8080` target Traefik) |
| `frappe-websocket` | Server Realtime Socket.IO (`websocket:9000`) |
| `frappe-scheduler` | Penjadwal Tugas Otomatis (`bench schedule`) |
| `frappe-worker-default` | Pekerja Tugas Latar Belakang (`bench worker`) |

---

## 🚀 Langkah 1: Jalankan Stack Frappe
```bash
cd /opt/setupserv
make app-up APP=frappe
```
*(Docker akan otomatis menyalakan seluruh 8 layanan daemon dan 1 kontainer configurator)*.

---

## 🟢 OPSI A: Membuat Site Baru (Fresh Install)

Jika Anda ingin membuat site Frappe/ERPNext baru dari nol:

```bash
# 1. Masuk ke kontainer backend
docker exec -it frappe-backend bash

# 2. Buat site baru (ganti hris.anterinmsi.my.id dengan domain Anda)
bench new-site hris.anterinmsi.my.id \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --admin-password "PasswordAdminBaru123!" \
  --no-mariadb-socket

# 3. Install aplikasi ERPNext & HRMS
bench --site hris.anterinmsi.my.id install-app erpnext
bench --site hris.anterinmsi.my.id install-app hrms

# 4. Set sebagai default site lalu keluar
bench use hris.anterinmsi.my.id
exit
```

---

## 🔄 OPSI B: Restore dari Backup Lama (HRIS)

Jika Anda memiliki file backup Frappe lama (`.sql.gz` dan `.tgz`):

### 1. Salin File Backup dari Server ke Dalam Kontainer
```bash
docker exec frappe-backend mkdir -p /tmp/backup
docker cp /tmp/hris-backup/. frappe-backend:/tmp/backup/
```

### 2. Jalankan Restore Data & Migrasi
```bash
# A. Masuk ke kontainer backend
docker exec -it frappe-backend bash

# B. Buat site dengan nama domain sesuai backup Anda
bench new-site hris.anterinmsi.my.id \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --admin-password "PasswordAdminBaru123!" \
  --no-mariadb-socket

# C. Restore database + public files + private files sekaligus
bench --site hris.anterinmsi.my.id restore /tmp/backup/*-database.sql.gz \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --with-public-files /tmp/backup/*-files.tgz \
  --with-private-files /tmp/backup/*-private-files.tgz

# D. Install app & jalankan migrasi schema ke v15
bench --site hris.anterinmsi.my.id install-app erpnext
bench --site hris.anterinmsi.my.id install-app hrms
bench --site hris.anterinmsi.my.id migrate

# E. Set sebagai default site lalu keluar
bench use hris.anterinmsi.my.id
exit
```

---

## 🕹️ Perintah Pengelolaan

| Perintah | Fungsi |
| :--- | :--- |
| `make app-up APP=frappe` | Menyalakan / redeploy stack Frappe |
| `make app-status APP=frappe` | Cek status kesehatan kontainer Frappe |
| `make app-logs APP=frappe` | Lihat log semua layanan Frappe |
| `make app-down APP=frappe` | Matikan Frappe (**data aman** di persistent volume) |
