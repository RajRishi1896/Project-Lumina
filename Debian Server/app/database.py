"""Database initialization and constants for Lumina EduMesh Hub."""
import os
import sqlite3
import uuid
import time
import logging
import asyncio
from logging.handlers import RotatingFileHandler
from datetime import datetime

UPLOAD_DIR = "uploads"
DB_PATH = "data/hub.db"
PROFILE_ICONS_DIR = "profile_icons"
THUMBNAILS_DIR = "thumbnails"

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(PROFILE_ICONS_DIR, exist_ok=True)
os.makedirs(THUMBNAILS_DIR, exist_ok=True)

_startup_time = time.time()

admin_handler = RotatingFileHandler('data/admin_actions.log', maxBytes=2*1024*1024, backupCount=3)
admin_logger = logging.getLogger('admin_actions')
admin_logger.setLevel(logging.INFO)
admin_logger.addHandler(admin_handler)
_admin_log_lock = asyncio.Lock()


async def log_admin_action(username: str, action: str):
    try:
        async with _admin_log_lock:
            conn = sqlite3.connect(DB_PATH, timeout=5.0)
            try:
                cur = conn.cursor()
                cur.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)')
                cur.execute('INSERT OR IGNORE INTO settings (key, value) VALUES ("log_retention", "30d")')
                cur.execute("SELECT value FROM settings WHERE key = 'log_retention'")
                row = cur.fetchone()
                retention = row[0] if row else "30d"
            finally:
                conn.close()
    except Exception as e:
        retention = "30d"

    if retention == "none":
        return

    now = datetime.now()
    await asyncio.to_thread(_write_log, now.isoformat(), username, action, retention)


def _write_log(timestamp, username, action, retention):
    log_line = f"{timestamp} - {username}: {action}\n"
    try:
        with open("data/admin_actions.log", "a") as f:
            f.write(log_line)
    except Exception as e:
        logging.error(f"Could not write admin action log: {e}")
    _prune_logs_if_needed(retention)


def _prune_logs_if_needed(retention):
    if retention == "never":
        return

    try:
        delta = None
        if retention == "24h":
            delta = 24 * 3600
        elif retention == "7d":
            delta = 7 * 24 * 3600
        elif retention == "30d":
            delta = 30 * 24 * 3600
        elif retention == "3m":
            delta = 90 * 24 * 3600
        elif retention == "6m":
            delta = 180 * 24 * 3600

        if delta is not None:
            cutoff = datetime.now().timestamp() - delta
            kept_lines = []
            if os.path.exists("data/admin_actions.log"):
                with open("data/admin_actions.log", "r") as f:
                    for line in f:
                        parts = line.split(" - ", 1)
                        try:
                            log_time = datetime.fromisoformat(parts[0])
                            if log_time.timestamp() >= cutoff:
                                kept_lines.append(line)
                        except Exception:
                            kept_lines.append(line)
                with open("data/admin_actions.log", "w") as f:
                    f.writelines(kept_lines)
    except Exception as e:
        logging.error(f"Error pruning logs: {e}")


def init_db():
    from app.dependencies import hash_password

    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    conn.execute('PRAGMA journal_mode=WAL')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS scholars (id TEXT PRIMARY KEY, name TEXT UNIQUE)')
    c.execute('CREATE TABLE IF NOT EXISTS resources (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, file_path TEXT, type TEXT)')
    c.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, hashed_password TEXT, name TEXT, department TEXT, scholar_id TEXT, reset_required INTEGER DEFAULT 0, role TEXT NOT NULL DEFAULT "teacher")')
    try:
        c.execute('ALTER TABLE users ADD COLUMN name TEXT')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE users ADD COLUMN department TEXT')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE users ADD COLUMN scholar_id TEXT')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT "teacher"')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE users ADD COLUMN reset_required INTEGER DEFAULT 0')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE scholars ADD COLUMN hashed_password TEXT')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE scholars ADD COLUMN reset_required INTEGER DEFAULT 0')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE scholars ADD COLUMN grade TEXT DEFAULT ""')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE scholars ADD COLUMN username TEXT')
    except sqlite3.OperationalError:
        pass
    c.execute("UPDATE scholars SET username = name WHERE username IS NULL OR username = ''")
    try:
        c.execute('DROP INDEX IF EXISTS idx_scholars_name')
    except Exception:
        pass
    try:
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_scholars_username ON scholars(username)')
    except Exception:
        pass
    try:
        c.execute('CREATE INDEX IF NOT EXISTS idx_scholars_name ON scholars(name)')
    except Exception:
        pass
    c.execute('CREATE TABLE IF NOT EXISTS weekly_study (scholar_id TEXT PRIMARY KEY, total_seconds INTEGER DEFAULT 0, streak_days INTEGER DEFAULT 0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    try:
        c.execute('ALTER TABLE weekly_study ADD COLUMN streak_days INTEGER DEFAULT 0')
    except sqlite3.OperationalError:
        pass
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    c.execute('CREATE TABLE IF NOT EXISTS study_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, start_time DATETIME, end_time DATETIME, duration_seconds INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    try:
        c.execute('ALTER TABLE sessions ADD COLUMN role TEXT')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE sessions ADD COLUMN encryption_key TEXT')
    except sqlite3.OperationalError:
        pass
    c.execute('CREATE TABLE IF NOT EXISTS subject_minutes (scholar_id TEXT NOT NULL, subject_name TEXT NOT NULL, minutes INTEGER DEFAULT 0, PRIMARY KEY (scholar_id, subject_name))')
    try:
        c.execute('ALTER TABLE sessions ADD COLUMN last_accessed DATETIME')
    except sqlite3.OperationalError:
        pass
    c.execute('CREATE TABLE IF NOT EXISTS refresh_tokens (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expires_at TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS persistent_keys (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expires_at TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')

    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='subjects'")
    if c.fetchone():
        c.execute("PRAGMA table_info(subjects)")
        cols = [col[1] for col in c.fetchall()]
        if 'class_name' not in cols:
            try:
                c.execute("SELECT name, symbol FROM subjects")
                existing = c.fetchall()
                c.execute("DROP TABLE subjects")
                c.execute('CREATE TABLE subjects (name TEXT, symbol TEXT, class_name TEXT, PRIMARY KEY (name, class_name))')
                for name, symbol in existing:
                    c.execute("INSERT OR IGNORE INTO subjects (name, symbol, class_name) VALUES (?, ?, ?)", (name, symbol, 'All Classes'))
            except Exception as e:
                logging.error(f"Migration error: {e}")
    else:
        c.execute('CREATE TABLE IF NOT EXISTS subjects (name TEXT, symbol TEXT, class_name TEXT, PRIMARY KEY (name, class_name))')

    try:
        c.execute('ALTER TABLE subjects ADD COLUMN id TEXT')
    except sqlite3.OperationalError:
        pass
    c.execute("SELECT rowid FROM subjects WHERE id IS NULL")
    for (rowid,) in c.fetchall():
        c.execute("UPDATE subjects SET id = ? WHERE rowid = ?", (f"SUBJ-{uuid.uuid4().hex[:8]}", rowid))
    try:
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_subjects_id ON subjects(id)')
    except Exception:
        pass
    try:
        c.execute('ALTER TABLE resources ADD COLUMN grade TEXT DEFAULT ""')
    except sqlite3.OperationalError:
        pass

    c.execute('CREATE TABLE IF NOT EXISTS grades (name TEXT PRIMARY KEY)')
    c.execute('SELECT count(*) FROM grades')
    if c.fetchone()[0] == 0:
        for g in ["Grade 9", "Grade 10", "Grade 11", "Grade 12"]:
            c.execute("INSERT OR IGNORE INTO grades (name) VALUES (?)", (g,))

    try:
        default_pwd = hash_password("lumina2026")
        admin_id = f"LUMINA_01-T{uuid.uuid4().hex}"
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id) VALUES (?, ?, ?, ?, ?)", ("admin", default_pwd, "Administrator", "System", admin_id))
        logging.info("═" * 50)
        logging.info("  DEFAULT ADMIN PASSWORD: lumina2026")
        logging.info("  CHANGE IT IMMEDIATELY via Dashboard → Settings → Change Password")
        logging.info("═" * 50)
    except sqlite3.IntegrityError:
        pass

    # Do NOT force-reset admin password on every restart — let admin keep their password

    c.execute('SELECT count(*) FROM subjects')
    if c.fetchone()[0] == 0:
        defaults = [
            ("Mathematics", "calculator", "All Classes"),
            ("Science", "atom", "All Classes"),
            ("History", "globe", "All Classes"),
            ("Literature", "book", "All Classes"),
            ("Computer Science", "laptop", "All Classes"),
            ("General", "folder", "All Classes"),
        ]
        c.executemany("INSERT INTO subjects (name, symbol, class_name) VALUES (?, ?, ?)", defaults)

    try:
        c.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)')
        c.execute('INSERT OR IGNORE INTO settings (key, value) VALUES ("log_retention", "30d")')
    except Exception as e:
        logging.error(f"Could not create settings table: {e}")

    c.execute("DELETE FROM weekly_study WHERE updated_at < datetime('now', '-7 days')")

    try:
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    except sqlite3.OperationalError:
        pass
    conn.commit()
    conn.close()


async def auto_register_if_new(scholar_id: str, name: str = "Roaming Scholar"):
    def _run():
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            c = conn.cursor()
            c.execute("INSERT OR IGNORE INTO scholars (id, name) VALUES (?, ?)", (scholar_id, name))
            conn.commit()
        finally:
            conn.close()
    await asyncio.to_thread(_run)


init_db()

conn = sqlite3.connect(DB_PATH, timeout=5.0)
cur = conn.cursor()
cur.execute('UPDATE users SET role = "admin" WHERE username = "admin"')
conn.commit()
conn.close()
