#!/bin/bash
# Purpose: Backup the Lumina Hub database and critical small data.
# Usage:   sudo ./backup_hub.sh
# Args:    None
# Idempotent: Yes, creates timestamped backup directory each run.
# Note:    Uploads (PDFs, videos, ZIM archives) are NOT backed up.
#          They are large and can be re-uploaded by teachers.
#          Only the database (accounts, progress, metadata) is backed up.
set -e
cd "$(dirname "$0")"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

echo "[INFO] Starting backup to $BACKUP_DIR ..."

# 1. Database (WAL-safe snapshot)
echo "[INFO] Backing up database..."
if [ -f "data/hub.db" ]; then
    sqlite3 data/hub.db ".backup '$BACKUP_DIR/hub.db'"
    DB_SIZE=$(du -h "$BACKUP_DIR/hub.db" | cut -f1)
    echo "  -> hub.db backed up ($DB_SIZE)"
else
    echo "  -> hub.db not found, skipping"
fi

# 2. Logs
cp data/hub.log "$BACKUP_DIR/" 2>/dev/null || true
cp data/admin_actions.log "$BACKUP_DIR/" 2>/dev/null || true

# 3. ZIM config (tiny metadata)
cp data/zim_cache_config.json "$BACKUP_DIR/" 2>/dev/null || true

# 4. Profile icons (one small image per student)
if [ -d "profile_icons" ] && [ "$(ls -A profile_icons 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/profile_icons.tar.gz" -C . profile_icons/
    echo "  -> profile_icons.tar.gz ($(du -h "$BACKUP_DIR/profile_icons.tar.gz" | cut -f1))"
fi

# 5. Verify backup integrity
if [ -f "$BACKUP_DIR/hub.db" ]; then
    echo "[INFO] Verifying backup integrity..."
    TMP_DB=$(mktemp /tmp/lumina_verify_XXXXXX.db)
    cp "$BACKUP_DIR/hub.db" "$TMP_DB"

    INTEGRITY=$(sqlite3 "$TMP_DB" "PRAGMA integrity_check;" 2>/dev/null)
    if [ "$INTEGRITY" = "ok" ]; then
        echo "  -> Integrity check: PASS"
    else
        echo "  -> Integrity check: FAIL ($INTEGRITY)"
        rm -f "$TMP_DB"
        exit 1
    fi

    for TABLE in users sessions resources subjects grades courses enrollments quiz_attempts; do
        COUNT=$(sqlite3 "$TMP_DB" "SELECT COUNT(*) FROM $TABLE;" 2>/dev/null || echo "?")
        echo "  -> $TABLE: $COUNT rows"
    done

    rm -f "$TMP_DB"
    echo "  -> Verification complete"
fi

# Summary
echo ""
echo "========================================="
echo "  Backup complete: $BACKUP_DIR"
ls -lh "$BACKUP_DIR/"
echo ""
echo "  Restores: accounts, progress, enrollments, resources metadata,"
echo "            profile icons, logs."
echo "  NOT backed up: uploaded PDFs/videos/ZIM (re-upload from source)."
echo "  To restore: sudo ./restore_hub.sh $BACKUP_DIR"
echo "========================================="
