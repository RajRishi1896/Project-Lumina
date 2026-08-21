#!/bin/bash
# Purpose: Emergency admin password reset. Resets the dashboard admin
#          password to "lumina2026" by directly updating the SQLite database.
# Usage:   sudo ./reset_admin.sh
# Args:    None
# Idempotent: Yes, always resets to the same password regardless of the
#             current state.
set -e

echo "[WARNING] Initiating Emergency Password Reset..."

# Ensure we are in the correct directory
cd "$(dirname "$0")"

./venv/bin/python3 -c '
import sqlite3
import bcrypt

print("Generating secure hash...")
hashed = bcrypt.hashpw(b"lumina2026", bcrypt.gensalt()).decode()

try:
    print("Connecting to Hub Database...")
    conn = sqlite3.connect("data/hub.db")
    c = conn.cursor()
    c.execute("UPDATE users SET hashed_password = ? WHERE username = ?", (hashed, "admin"))
    conn.commit()
    conn.close()
    print("\n[SUCCESS] The Admin password has been reset to: lumina2026")
    print("You can now log into the Dashboard.")
except Exception as e:
    print(f"\n[ERROR] Could not reset password. {e}")
'
read -p "Press Enter to close..."
