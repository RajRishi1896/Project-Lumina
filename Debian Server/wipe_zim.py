"""Wipe old ZIM index and re-import from disk."""
import sqlite3
import os
import time

DB = "data/hub.db"
UPLOADS = "uploads"
FILENAME = "ZIM-b9a13790b828.zim"

conn = sqlite3.connect(DB)
c = conn.cursor()

# 1. Check current state
count = c.execute("SELECT COUNT(*) FROM zim_articles").fetchone()[0]
print(f"Current articles: {count}")

archives = c.execute("SELECT id, zim_path FROM zim_archives").fetchall()
for aid, zpath in archives:
    print(f"  archive {aid}: {zpath}")

# 2. Delete old index
print("Deleting old FTS...")
c.execute("DROP TABLE IF EXISTS zim_articles_fts")
print("Deleting old articles...")
c.execute("DELETE FROM zim_articles")
print("Deleting old archives...")
c.execute("DELETE FROM zim_archives")
print("Deleting kiwix resources...")
c.execute("DELETE FROM resources WHERE resource_type = 'kiwix'")
conn.commit()
conn.close()
print("Old index wiped.")

# 3. Verify file exists
fpath = os.path.join(UPLOADS, FILENAME)
fsize = os.path.getsize(fpath) if os.path.isfile(fpath) else 0
print(f"ZIM file: {fpath} ({fsize / (1024**3):.1f} GB)")
if fsize == 0:
    print("ERROR: File not found!")
    exit(1)

print("Ready for re-import. Run import-local-zim endpoint.")
