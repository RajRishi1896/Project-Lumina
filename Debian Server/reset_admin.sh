#!/bin/bash
# Purpose: Emergency admin password reset. Resets to default password,
#          hashes it with bcrypt, and updates the database.
# Usage:   sudo ./reset_admin.sh
# Args:    None
# Idempotent: Yes, always resets to the default password regardless of the
#             current state.
set -e

echo "[WARNING] Initiating Emergency Password Reset..."

# Ensure we are in the correct directory
cd "$(dirname "$0")"

./venv/bin/python3 -c '
import sqlite3
import bcrypt

default_pwd = "lumina2026"
print("Generating secure hash...")
hashed = bcrypt.hashpw(default_pwd.encode(), bcrypt.gensalt()).decode()

try:
    print("Connecting to Hub Database...")
    conn = sqlite3.connect("data/hub.db")
    c = conn.cursor()
    c.execute("UPDATE users SET hashed_password = ? WHERE username = ?", (hashed, "admin"))
    conn.commit()
    conn.close()

    print(f"\n[SUCCESS] Admin password has been reset.")
    print(f"  Password: {default_pwd}")
    print("You can now log into the Dashboard.")
except Exception as e:
    print(f"\n[ERROR] Could not reset password. {e}")
'
read -p "Press Enter to close..."
