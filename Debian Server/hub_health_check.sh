#!/bin/bash
set -e
# Lumina Hub - Pre-boot Health Check

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
