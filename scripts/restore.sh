#!/bin/sh
set -eu

# ==============================================================================
# Server Bootstrap Framework — Manual Restore Script (POSIX sh)
# Usage: restore.sh [YYYY-MM-DD_HH-MM-SS] [all|configs]
# ==============================================================================

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

log_error() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ERROR: $1" >&2
}

REMOTE_NAME="${BACKUP_REMOTE_NAME:-gdrive}"
REMOTE_PATH="${BACKUP_REMOTE_PATH:-bootstrap-backups}"
RCLONE_CONF="/secrets/rclone.conf"
RESTORE_DIR="/backups/restore"
TEMP_RESTORE_DIR="/tmp/restore"

RCLONE_CMD="rclone"
if [ -f "${RCLONE_CONF}" ]; then
    RCLONE_CMD="rclone --config ${RCLONE_CONF}"
fi

TARGET_TIMESTAMP="${1:-}"
SCOPE="${2:-configs}"

# If no timestamp argument is provided, list available backups
if [ -z "${TARGET_TIMESTAMP}" ]; then
    log "================================================================="
    log "AVAILABLE REMOTE BACKUPS (${REMOTE_NAME}:${REMOTE_PATH}):"
    log "================================================================="
    ${RCLONE_CMD} lsd "${REMOTE_NAME}:${REMOTE_PATH}" || {
        log_error "Failed to list remote backups. Check rclone configuration."
        exit 1
    }
    log "================================================================="
    log "Usage: $0 [YYYY-MM-DD_HH-MM-SS] [all|configs]"
    exit 0
fi

log "Starting restore process for backup timestamp: ${TARGET_TIMESTAMP}..."

# 1. Download Backup from Remote
DOWNLOAD_DIR="${RESTORE_DIR}/${TARGET_TIMESTAMP}"
mkdir -p "${DOWNLOAD_DIR}"

log "Downloading backup files from ${REMOTE_NAME}:${REMOTE_PATH}/${TARGET_TIMESTAMP}/ to ${DOWNLOAD_DIR}..."
if ${RCLONE_CMD} copy "${REMOTE_NAME}:${REMOTE_PATH}/${TARGET_TIMESTAMP}/" "${DOWNLOAD_DIR}/"; then
    log "Backup files downloaded successfully."
else
    log_error "Failed to download backup files from remote storage!"
    exit 1
fi

# 2. Decryption Phase (if encrypted)
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"

if [ -f "${DOWNLOAD_DIR}/configs.tar.gz.enc" ]; then
    log "Encrypted configuration archive detected. Decrypting..."
    if [ -z "${ENCRYPTION_KEY}" ] || [ "${ENCRYPTION_KEY}" = "CHANGE_ME" ]; then
        log_error "BACKUP_ENCRYPTION_KEY is required to decrypt this archive!"
        exit 1
    fi

    if command -v openssl >/dev/null 2>&1; then
        openssl enc -d -aes-256-cbc -pbkdf2 -salt \
            -in "${DOWNLOAD_DIR}/configs.tar.gz.enc" \
            -out "${DOWNLOAD_DIR}/configs.tar.gz" \
            -pass pass:"${ENCRYPTION_KEY}"
        log "Decryption completed: ${DOWNLOAD_DIR}/configs.tar.gz"
    else
        log_error "openssl command not found. Cannot decrypt archive!"
        exit 1
    fi
fi

# 3. Inspection & Confirmation
mkdir -p "${TEMP_RESTORE_DIR}/${TARGET_TIMESTAMP}"

if [ -f "${DOWNLOAD_DIR}/configs.tar.gz" ]; then
    log "================================================================="
    log "CONTENTS OF CONFIGURATION ARCHIVE:"
    log "================================================================="
    tar -tzf "${DOWNLOAD_DIR}/configs.tar.gz" | head -n 30
    log "... (showing first 30 entries)"
    log "================================================================="

    printf "Extract configuration archive to %s? [y/N]: " "${TEMP_RESTORE_DIR}/${TARGET_TIMESTAMP}"
    read -r confirmation
    case "${confirmation}" in
        [yY][eE][sS]|[yY])
            tar -xzf "${DOWNLOAD_DIR}/configs.tar.gz" -C "${TEMP_RESTORE_DIR}/${TARGET_TIMESTAMP}"
            log "Configuration files extracted to ${TEMP_RESTORE_DIR}/${TARGET_TIMESTAMP}"
            log "Review extracted files before manually applying to /configs."
            ;;
        *)
            log "Extraction cancelled by user."
            ;;
    esac
else
    log_error "No valid configs.tar.gz file found in downloaded backup!"
    exit 1
fi

log "Restore process finished."
exit 0
