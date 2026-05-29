#!/bin/bash
set -e
# Lumina Hub - Emergency Admin Reset
# Double-click or run this script to reset the dashboard password to 'lumina2026'

echo "[WARNING] Initiating Emergency Password Reset..."

# Ensure we are in the correct directory
cd "$(dirname "$0")"

python3 -c '
import sqlite3
from passlib.context import CryptContext

print("Generating secure hash...")
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
default_hash = pwd_context.hash("lumina2026")

try:
    print("Connecting to Hub Database...")
    conn = sqlite3.connect("data/hub.db")
    c = conn.cursor()
    c.execute("UPDATE users SET hashed_password = ? WHERE username = ?", (default_hash, "admin"))
    conn.commit()
    conn.close()
    print("\n[SUCCESS] The Admin password has been reset to: lumina2026")
    print("You can now log into the Dashboard.")
except Exception as e:
    print(f"\n[ERROR] Could not reset password. {e}")
'
read -p "Press Enter to close..."
