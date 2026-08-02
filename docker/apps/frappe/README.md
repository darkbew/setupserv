# 🏢 Panduan Instalasi Frappe v15 (ERPNext + HRMS + LMS)

> Panduan ini menjelaskan cara menjalankan **Frappe Framework v15** berbasis arsitektur resmi **`frappe_docker`** yang diadaptasi secara sempurna ke platform setupserv Anda (menggunakan Traefik, `proxy-net`, `backend-net`, dan otomatisasi `configurator`).

---

## 📦 Komponen Yang Berjalan (9 Kontainer Terkoordinasi)

| Kontainer | Fungsi / Peran |
| :--- | :--- |
| `frappe-mariadb` | Database MariaDB 11.4 khusus Frappe |
| `frappe-redis-cache` | Redis Cache (mempercepat akses halaman) |
| `frappe-redis-queue` | Redis Queue (antrian tugas latar belakang) |
| `frappe-configurator` | Inisialisasi otomatis `common_site_config.json` (set host DB & Redis) |
| `frappe-backend` | Server Aplikasi Gunicorn Python (`backend:8000`) |
| `frappe-frontend` | Nginx Web Server & Static Assets (`frontend:8080` target Traefik) |
| `frappe-websocket` | Server Realtime Socket.IO (`websocket:9000`) |
| `frappe-scheduler` | Penjadwal Tugas Otomatis (`bench schedule`) |
| `frappe-worker-default` | Pekerja Tugas Latar Belakang (`bench worker`) |

---

## 🚀 Langkah Instalasi & Deployment

### 1. Jalankan Stack Frappe
```bash
cd /opt/setupserv
make app-up APP=frappe
```

### 2. Buat Site Baru & Install Aplikasi
Setelah `frappe-configurator` selesai dan kontainer berjalan sehat:

```bash
# Masuk ke kontainer backend
docker exec -it frappe-backend bash

# Buat site baru (ganti erp.domainanda.com dengan domain Anda)
bench new-site erp.domainanda.com \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
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

## 🔄 Langkah Restore dari Backup Lama (HRIS)

If you have a previous Frappe backup (`.sql.gz` and `.tgz` files):

### 1. Salin File Backup ke Kontainer
```bash
docker exec frappe-backend mkdir -p /tmp/backup
docker cp /tmp/hris-backup/. frappe-backend:/tmp/backup/
```

### 2. Restore Site & Migrasi
```bash
docker exec -it frappe-backend bash

# Buat site dengan nama domain sesuai backup
bench new-site hris.anterinmsi.my.id \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --admin-password "PasswordAdminBaru123!" \
  --no-mariadb-socket

# Restore database + files
bench --site hris.anterinmsi.my.id restore /tmp/backup/*-database.sql.gz \
  --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
  --with-public-files /tmp/backup/*-files.tgz \
  --with-private-files /tmp/backup/*-private-files.tgz

# Install app & migrasi
bench --site hris.anterinmsi.my.id install-app erpnext
bench --site hris.anterinmsi.my.id install-app hrms
bench --site hris.anterinmsi.my.id migrate

bench use hris.anterinmsi.my.id
exit
```

---

## 🕹️ Perintah Pengelolaan

| Perintah | Fungsi |
| :--- | :--- |
| `make app-up APP=frappe` | Menyalakan / redeploy stack Frappe |
| `make app-status APP=frappe` | Cek status 9 kontainer Frappe |
| `make app-logs APP=frappe` | Lihat log semua layanan Frappe |
| `make app-down APP=frappe` | Matikan Frappe (**data aman** di persistent volume) |
