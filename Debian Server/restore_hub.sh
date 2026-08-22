#!/bin/bash
# Purpose: Restore the Lumina Hub from a backup created by backup_hub.sh.
# Usage:   sudo ./restore_hub.sh backups/20260715_120000
# Args:    $1 = path to backup directory (required)
# Idempotent: No, overwrites existing data. Stop the server first.
set -e

if [ -z "$1" ]; then
    echo "Usage: sudo ./restore_hub.sh <backup_directory>"
    echo ""
    echo "Available backups:"
    ls -1d backups/*/ 2>/dev/null || echo "  (none)"
    exit 1
fi

BACKUP_DIR="$1"
cd "$(dirname "$0")"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "[ERROR] Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "[WARNING] This will OVERWRITE current data with the backup."
echo "  Backup: $BACKUP_DIR"
ls -lh "$BACKUP_DIR/"
echo ""
echo "  Restores: database (accounts, progress, enrollments),"
echo "            profile icons, logs."
echo "  NOT restored: uploaded files (re-upload from source)."
echo ""
read -p "Type 'RESTORE' to confirm: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Aborted."
    exit 1
fi

echo "[INFO] Stopping Lumina Hub service..."
systemctl stop lumina-hub.service 2>/dev/null || true

# 1. Restore database
if [ -f "$BACKUP_DIR/hub.db" ]; then
    echo "[INFO] Restoring database..."
    mkdir -p data
    cp "$BACKUP_DIR/hub.db" data/hub.db
    echo "  -> hub.db restored"
fi

# 2. Restore profile icons
if [ -f "$BACKUP_DIR/profile_icons.tar.gz" ]; then
    echo "[INFO] Restoring profile icons..."
    tar -xzf "$BACKUP_DIR/profile_icons.tar.gz" -C .
    echo "  -> profile_icons/ restored"
fi

# 3. Fix permissions
chmod -R 755 profile_icons/ 2>/dev/null || true

echo "[INFO] Starting Lumina Hub service..."
systemctl start lumina-hub.service 2>/dev/null || echo "  -> Start manually: sudo systemctl start lumina-hub"

echo ""
echo "========================================="
echo "  Restore complete from: $BACKUP_DIR"
echo ""
echo "  NOTE: Uploaded files (PDFs, videos, quizzes) were NOT backed up."
echo "  Re-upload them from the original source via the teacher dashboard."
echo "  The database knows what files existed (titles, metadata) but the"
echo "  actual files must be re-uploaded."
echo "========================================="
