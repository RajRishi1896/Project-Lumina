#!/bin/bash
# Purpose: Emergency admin password reset. Generates a new random password,
#          hashes it with bcrypt, updates the database, and saves the
#          plaintext to data/admin_bootstrap.txt.
# Usage:   sudo ./reset_admin.sh
# Args:    None
# Idempotent: Yes, always generates a new random password regardless of the
#             current state.
set -e

echo "[WARNING] Initiating Emergency Password Reset..."

# Ensure we are in the correct directory
cd "$(dirname "$0")"

./venv/bin/python3 -c '
import sqlite3
import secrets
import bcrypt

new_pwd = secrets.token_urlsafe(12)
print("Generating secure hash...")
hashed = bcrypt.hashpw(new_pwd.encode(), bcrypt.gensalt()).decode()

try:
    print("Connecting to Hub Database...")
    conn = sqlite3.connect("data/hub.db")
    c = conn.cursor()
    c.execute("UPDATE users SET hashed_password = ? WHERE username = ?", (hashed, "admin"))
    conn.commit()
    conn.close()

    import os
    os.makedirs("data", exist_ok=True)
    with open("data/admin_bootstrap.txt", "w") as f:
        f.write(new_pwd)

    print(f"\n[SUCCESS] Admin password has been reset.")
    print(f"  New password: {new_pwd}")
    print(f"  Saved to:     data/admin_bootstrap.txt")
    print("You can now log into the Dashboard.")
except Exception as e:
    print(f"\n[ERROR] Could not reset password. {e}")
'
read -p "Press Enter to close..."
