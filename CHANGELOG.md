# Changelog

Semua perubahan penting pada proyek **Setupserv Infrastructure Framework** dicatat di file ini.

Format changelog mengikuti prinsip **Keep a Changelog** dan menggunakan **Semantic Versioning (SemVer)**.

---

## [1.0.0] - 2026-08-01

### Added
- **Dual-Mode Ingress Architecture**: Mendukung mode switching dinamis antara Cloudflare Tunnel (`make ingress-tunnel`) dan Direct Public IP dengan otomatisasi Let's Encrypt TLS (`make ingress-public`).
- **Automated Backup Worker Engine**: Layanan latar belakang rclone terenkripsi AES-256-CBC dengan upload otomatis ke Google Drive / Remote Storage dan skrip `restore.sh`.
- **Automatic Grafana Dashboards**: Provisioning otomatis dashboard Docker, Host, dan Traefik.
- **Unified Makefile Management**: Antarmuka CLI terpusat untuk kontrol platform Layer 2 dan deployment aplikasi Layer 3 (`make app-up`, `make app-status`, `make app-logs`, `make app-down`).

### Fixed
- **Critical `.gitignore` Fix**: Menghapus rule global `*.json` yang sebelumnya mengecualikan dashboard Grafana dari repository Git.
- **Cron Injection Security Fix**: Sanitasi parameter `BACKUP_SCHEDULE` pada `compose.backup.yaml` menggunakan `printf` dan `tr` untuk mencegah shell injection.
- **Top-Level Variable Scope Fix**: Menghapus penggunaan kata kunci `local` di luar fungsi Bash pada `scripts/deploy-platform.sh`.
- **Conditional Tunnel Validation**: `deploy-platform.sh` kini melewatkan validasi token Cloudflare jika berjalan dalam mode public ingress (`INGRESS_MODE=public`).
- **Dynamic Entrypoint Support**: Memperbarui router Grafana, Uptime Kuma, dan Dozzle pada `compose.monitoring.yaml` agar menggunakan `${APP_ENTRYPOINT:-web}`.

### Removed
- Menghapus folder `configs/loki/` dan `configs/promtail/` yang tidak digunakan oleh stack.
- Menghapus folder `docs/` berisi blueprint arsitektur lama yang telah digantikan oleh `README.md` terpusat.
- Menghapus file `data/traefik/acme.json` dari pelacakan versi Git (dibuat secara otomatis saat runtime dengan izin 600).
- Menghapus variabel port internal yang tidak terpakai dari `.env.example`.