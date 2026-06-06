#!/bin/bash
# Purpose: Pre-boot integrity check for the Lumina Hub. Verifies that all
#          required files and directories exist before launching the server.
#          Creates missing directories automatically; aborts on missing
#          critical files.
# Usage:   ./hub_health_check.sh
# Args:    None
# Idempotent: Yes — creates missing directories if needed, then launches
#             the server.
set -e

cd "$(dirname "$0")"

echo "[INFO] Running Hub Integrity Check..."

# Required files and directories
REQUIRED_FILES=("main.py" "requirements.txt" "app/api.py" "static/index.html")
REQUIRED_DIRS=("uploads" "data" "app" "static")

MISSING=0

# Check Directories
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "[WARNING] Missing directory: $dir. Creating it..."
        mkdir -p "$dir"
    fi
done

# Check Files
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "[CRITICAL] Missing $file. Hub cannot start."
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo "[ERROR] Boot aborted due to missing critical files."
    exit 1
fi

echo "[SUCCESS] Health check passed. Launching Lumina Hub..."
./venv/bin/python3 main.py
