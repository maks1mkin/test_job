#!/bin/bash


set -euo pipefail

# ============================================
# CONFIGURATION AND VARIABLES
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please create config.env from config.env.example"
    exit 1
fi

source "$CONFIG_FILE"

# ============================================
# VARIABLES
# ============================================

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="postgresql_${DB_NAME}_${TIMESTAMP}"
LOCAL_BACKUP_DIR="${LOCAL_BACKUP_PATH}/postgresql"
BACKUP_FILE="${LOCAL_BACKUP_DIR}/${BACKUP_NAME}.sql"
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"
LOG_FILE="${SCRIPT_DIR}/logs/backup_${TIMESTAMP}.log"

# ============================================
# FUNCTIONS
# ============================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

create_directories() {
    mkdir -p "$LOCAL_BACKUP_DIR"
    mkdir -p "${SCRIPT_DIR}/logs"
}

# Database backup function
backup_postgresql() {
    log "Starting PostgreSQL backup for database: $DB_NAME"
    
    export PGPASSWORD="$DB_PASSWORD"
    pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -F p -f "$BACKUP_FILE"
    unset PGPASSWORD
    
    log "PostgreSQL backup completed: $BACKUP_FILE"
}

# Encryption
encrypt_backup() {
    if [[ "${ENABLE_ENCRYPTION}" == "true" ]]; then
        log "Encrypting backup..."
        
        if [[ "${ENCRYPTION_METHOD}" == "gpg" ]]; then
            gpg --batch --yes --passphrase "$ENCRYPTION_PASSWORD" \
                --symmetric --cipher-algo AES256 -o "$ENCRYPTED_FILE" "$BACKUP_FILE"
        else
            openssl enc -aes-256-cbc -salt -pbkdf2 \
                -in "$BACKUP_FILE" -out "$ENCRYPTED_FILE" \
                -k "$ENCRYPTION_PASSWORD"
        fi
        
        rm -f "$BACKUP_FILE"
        BACKUP_FILE="$ENCRYPTED_FILE"
        log "Encryption completed: $BACKUP_FILE"
    fi
}

# Remote storage upload
upload_to_s3() {
    log "Uploading to S3..."
    aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/${S3_PREFIX}$(basename "$BACKUP_FILE")" \
        --region "${S3_REGION:-us-east-1}"
    log "Upload to S3 completed"
}

upload_to_ftp() {
    log "Uploading to FTP..."
    curl -T "$BACKUP_FILE" \
        "ftp://${FTP_HOST}:${FTP_PORT}/${FTP_PATH}$(basename "$BACKUP_FILE")" \
        --user "${FTP_USER}:${FTP_PASSWORD}"
    log "Upload to FTP completed"
}

upload_to_ssh() {
    log "Uploading via SSH/SCP..."
    scp -P "${SSH_PORT}" "$BACKUP_FILE" \
        "${SSH_USER}@${SSH_HOST}:${SSH_PATH}/$(basename "$BACKUP_FILE")"
    log "Upload via SSH completed"
}

upload_backup() {
    case "$STORAGE_TYPE" in
        s3)
            upload_to_s3
            ;;
        ftp)
            upload_to_ftp
            ;;
        ssh)
            upload_to_ssh
            ;;
        local)
            log "Storage type is 'local', skipping remote upload"
            ;;
        *)
            log "WARNING: Unknown storage type: $STORAGE_TYPE"
            ;;
    esac
}

# Cleanup old backups
cleanup_local() {
    log "Cleaning up local backups older than $RETENTION_DAYS days..."
    find "$LOCAL_BACKUP_DIR" -type f -name "*.sql*" -mtime +"$RETENTION_DAYS" -delete
    log "Local cleanup completed"
}

cleanup_s3() {
    log "Cleaning up S3 backups older than $RETENTION_DAYS days..."
    CUTOFF_DATE=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d)
    
    aws s3 ls "s3://${S3_BUCKET}/${S3_PREFIX}" | while read -r line; do
        FILE_DATE=$(echo "$line" | awk '{print $1}')
        FILE_NAME=$(echo "$line" | awk '{print $4}')
        
        if [[ "$FILE_DATE" < "$CUTOFF_DATE" ]]; then
            aws s3 rm "s3://${S3_BUCKET}/${S3_PREFIX}${FILE_NAME}"
            log "Deleted old S3 backup: $FILE_NAME"
        fi
    done
}

cleanup_backups() {
    cleanup_local
    
    if [[ "$STORAGE_TYPE" == "s3" ]]; then
        cleanup_s3
    fi
}

# Health check
verify_backup() {
    if [[ -f "$BACKUP_FILE" ]]; then
        SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log "Backup file size: $SIZE"
        
        if [[ $(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE") -lt 1000 ]]; then
            log "ERROR: Backup file is too small, might be corrupted"
            return 1
        fi
    else
        log "ERROR: Backup file not found: $BACKUP_FILE"
        return 1
    fi
}

# ============================================
# MAIN
# ============================================

main() {
    log "========================================="
    log "Starting PostgreSQL backup process"
    log "Database Name: $DB_NAME"
    log "========================================="
    
    create_directories
    
    # Create backup
    backup_postgresql
    
    # Verify backup
    verify_backup || exit 1
    
    # Encrypt
    encrypt_backup
    
    # Upload
    upload_backup
    
    # Cleanup
    cleanup_backups
    
    log "========================================="
    log "Backup process completed successfully"
    log "========================================="
}


main "$@"
