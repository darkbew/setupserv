#!/bin/sh
set -eu

# ==============================================================================
# Server Bootstrap Framework — Automated Backup Script (POSIX sh)
# Runs inside the rclone container to archive, encrypt, and upload backups.
# ==============================================================================

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

log_error() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ERROR: $1" >&2
}

cleanup() {
    log "Backup execution interrupted or terminated."
    exit 130
}

trap cleanup INT TERM

log "================================================================="
log "Starting platform infrastructure backup routine..."
log "================================================================="

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOCAL_BACKUP_DIR="/backups/local/${TIMESTAMP}"

mkdir -p "${LOCAL_BACKUP_DIR}"

# 1. Backup Configurations
log "Archiving platform configuration files from /configs..."
if [ -d "/configs" ]; then
    tar -czf "${LOCAL_BACKUP_DIR}/configs.tar.gz" -C /configs .
    log "Configurations archived successfully: ${LOCAL_BACKUP_DIR}/configs.tar.gz"
else
    log_error "/configs directory not found! Skipping config archive."
fi

# 2. Named Volumes Note
log "NOTE: Docker named volumes (prometheus_data, etc.) must be backed up via host-side script."

# 3. Encryption Phase
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
if [ -n "${ENCRYPTION_KEY}" ] && [ "${ENCRYPTION_KEY}" != "CHANGE_ME" ]; then
    log "Encrypting backup archive with AES-256-CBC..."
    if command -v openssl >/dev/null 2>&1; then
        openssl enc -aes-256-cbc -pbkdf2 -salt \
            -in "${LOCAL_BACKUP_DIR}/configs.tar.gz" \
            -out "${LOCAL_BACKUP_DIR}/configs.tar.gz.enc" \
            -pass pass:"${ENCRYPTION_KEY}"
        rm -f "${LOCAL_BACKUP_DIR}/configs.tar.gz"
        log "Backup archive encrypted: configs.tar.gz.enc"
    else
        log "WARNING: openssl command not found in container. Archive will remain unencrypted."
    fi
else
    log "Encryption key not configured or set to default. Uploading unencrypted archive."
fi

# 4. Upload to Remote Storage via Rclone
REMOTE_NAME="${BACKUP_REMOTE_NAME:-gdrive}"
REMOTE_PATH="${BACKUP_REMOTE_PATH:-bootstrap-backups}"
RCLONE_CONF="/secrets/rclone.conf"

RCLONE_CMD="rclone"
if [ -f "${RCLONE_CONF}" ]; then
    RCLONE_CMD="rclone --config ${RCLONE_CONF}"
fi

log "Uploading backup to remote destination ${REMOTE_NAME}:${REMOTE_PATH}/${TIMESTAMP}/..."
if ${RCLONE_CMD} copy "${LOCAL_BACKUP_DIR}/" "${REMOTE_NAME}:${REMOTE_PATH}/${TIMESTAMP}/"; then
    log "Remote upload completed successfully."
else
    log_error "Remote upload failed!"
    exit 1
fi

# 5. Retention Management — Local
RETENTION_DAYS="${BACKUP_LOCAL_RETENTION_DAYS:-7}"
log "Cleaning up local backups older than ${RETENTION_DAYS} days..."
if [ -d "/backups/local" ]; then
    find /backups/local -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true
fi

# 6. Retention Management — Remote
REMOTE_RETENTION_DAYS=$((RETENTION_DAYS * 2))
log "Cleaning up remote backups older than ${REMOTE_RETENTION_DAYS} days..."
${RCLONE_CMD} delete "${REMOTE_NAME}:${REMOTE_PATH}" --min-age "${REMOTE_RETENTION_DAYS}d" --rmdirs 2>/dev/null || true

# 7. Update Last Success Healthcheck File
touch /backups/.last_backup_success
log "================================================================="
log "Backup routine completed successfully at ${TIMESTAMP}"
log "================================================================="
exit 0
