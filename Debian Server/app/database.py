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

RETENTION_DELTAS = {
    "24h": 86400,
    "7d": 604800,
    "30d": 2592000,
    "3m": 7776000,
    "6m": 15552000,
}


async def log_admin_action(username: str, action: str):
    now = datetime.now()
    await asyncio.to_thread(_write_log, now.isoformat(), username, action)


def _write_log(timestamp, username, action):
    """Reads retention, writes log entry, prunes if needed. All sync, runs in worker thread."""
    try:
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute("SELECT value FROM settings WHERE key = 'log_retention'")
            row = cur.fetchone()
            retention = row[0] if row else "30d"
        finally:
            conn.close()
    except Exception:
        retention = "30d"

    if retention == "none":
        return

    log_line = f"{timestamp} - {username}: {action}\n"
    try:
        with open("data/admin_actions.log", "a") as f:
            f.write(log_line)
    except Exception as e:
        logging.error(f"Could not write admin action log: {e}")
    _prune_logs_if_needed(retention)


def _prune_logs_if_needed(retention):
    # Throttle: only prune at most once per 60s to avoid rewriting the entire
    # file on every single admin action (SSD wear / write amplification).
    if retention == "never":
        return
    now = time.time()
    if now - getattr(_prune_logs_if_needed, '_last_run', 0) < 60:
        return
    _prune_logs_if_needed._last_run = now

    try:
        delta = RETENTION_DELTAS.get(retention, 2592000)
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
    conn.execute('PRAGMA busy_timeout=5000')
    conn.execute('PRAGMA cache_size=-8000')
    conn.execute('PRAGMA synchronous=NORMAL')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS scholars (id TEXT PRIMARY KEY, name TEXT UNIQUE)')
    c.execute('CREATE TABLE IF NOT EXISTS resources (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, file_path TEXT, type TEXT)')
    c.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, hashed_password TEXT, name TEXT, department TEXT, scholar_id TEXT, reset_required INTEGER DEFAULT 0, role TEXT NOT NULL DEFAULT "teacher")')
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
    try:
        c.execute('CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_resources_status ON resources(status)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_resources_subject ON resources(subject)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_resources_grade ON resources(grade)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_resources_type ON resources(resource_type)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_downloads_scholar ON scholar_downloads(scholar_id)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_subject_minutes_scholar ON subject_minutes(scholar_id)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_study_sessions_scholar ON study_sessions(scholar_id)')
        c.execute('CREATE INDEX IF NOT EXISTS idx_weekly_study_scholar ON weekly_study(scholar_id)')
    except Exception:
        pass
    c.execute('CREATE TABLE IF NOT EXISTS weekly_study (scholar_id TEXT PRIMARY KEY, total_seconds INTEGER DEFAULT 0, streak_days INTEGER DEFAULT 0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    c.execute('CREATE TABLE IF NOT EXISTS activity_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (scholar_id) REFERENCES scholars(id))')
    c.execute('CREATE TABLE IF NOT EXISTS study_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, start_time DATETIME, end_time DATETIME, duration_seconds INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, used INTEGER DEFAULT 0, expiry TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS subject_minutes (scholar_id TEXT NOT NULL, subject_name TEXT NOT NULL, minutes INTEGER DEFAULT 0, PRIMARY KEY (scholar_id, subject_name))')
    c.execute('CREATE TABLE IF NOT EXISTS refresh_tokens (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expires_at TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS persistent_keys (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expires_at TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')

    _migrate_schema(conn)

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

    c.execute("SELECT rowid FROM subjects WHERE id IS NULL")
    for (rowid,) in c.fetchall():
        c.execute("UPDATE subjects SET id = ? WHERE rowid = ?", (f"SUBJ-{uuid.uuid4().hex[:8]}", rowid))
    try:
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_subjects_id ON subjects(id)')
    except Exception:
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
    _migrate_resources_v2(conn)
    conn.commit()
    conn.close()


def _migrate_schema(conn):
    """Add missing columns to all tables using PRAGMA introspection."""
    for table, col_defs in {
        "users": {
            "name": "TEXT",
            "department": "TEXT",
            "scholar_id": "TEXT",
            "role": "TEXT NOT NULL DEFAULT 'teacher'",
            "reset_required": "INTEGER DEFAULT 0",
        },
        "scholars": {
            "hashed_password": "TEXT",
            "reset_required": "INTEGER DEFAULT 0",
            "grade": "TEXT DEFAULT ''",
            "username": "TEXT",
        },
        "weekly_study": {
            "streak_days": "INTEGER DEFAULT 0",
        },
        "sessions": {
            "role": "TEXT",
            "encryption_key": "TEXT",
            "last_accessed": "DATETIME",
            "used": "INTEGER DEFAULT 0",
            "expiry": "TEXT",
        },
        "subjects": {
            "id": "TEXT",
        },
        "resources": {
            "grade": "TEXT DEFAULT ''",
            "description": "TEXT DEFAULT ''",
            "chapter": "TEXT DEFAULT ''",
            "year": "INTEGER DEFAULT NULL",
            "superseded_by": "INTEGER DEFAULT NULL",
            "language": "TEXT DEFAULT 'en'",
            "resource_type": "TEXT DEFAULT 'textbook'",
            "source": "TEXT DEFAULT 'Unknown'",
            "license": "TEXT DEFAULT 'Internal Only'",
            "uploaded_by": "INTEGER DEFAULT NULL",
            "uploaded_at": "DATETIME DEFAULT CURRENT_TIMESTAMP",
        },
    }.items():
        existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()}
        for col, definition in col_defs.items():
            if col not in existing:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {col} {definition}")


def _migrate_resources_v2(conn):
    """Migrate resources table to v2 schema with all required metadata columns.

    Uses the caller's connection so we don't get 'database is locked' from
    two simultaneous connections in the same thread.
    """
    c = conn.cursor()
    # Check if migration already done
    c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='resources_v2'")
    if c.fetchone():
        return

    c.execute('''CREATE TABLE resources_v2 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        subject TEXT NOT NULL DEFAULT 'General',
        grade INTEGER DEFAULT 0,
        language TEXT NOT NULL DEFAULT 'en',
        resource_type TEXT NOT NULL DEFAULT 'textbook',
        filename TEXT,
        original_name TEXT,
        source TEXT DEFAULT 'Unknown',
        license TEXT DEFAULT 'Internal Only',
        uploaded_by INTEGER,
        uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        status TEXT NOT NULL DEFAULT 'approved',
        description TEXT,
        chapter TEXT,
        year INTEGER,
        superseded_by INTEGER REFERENCES resources_v2(id)
    )''')

    # Migrate existing data
    try:
        c.execute('''INSERT INTO resources_v2
            (id, title, subject, grade, resource_type, filename, original_name, status)
            SELECT id, title, COALESCE(subject, 'General'),
                CAST(CASE WHEN grade IS NULL OR grade = '' THEN '0' ELSE grade END AS INTEGER),
                COALESCE(type, 'textbook'),
                COALESCE(file_path, ''), COALESCE(file_path, ''),
                'approved'
            FROM resources''')
    except sqlite3.OperationalError:
        # Old table may have different columns
        pass

    # Drop old table and rename
    try:
        c.execute('DROP TABLE IF EXISTS resources')
        c.execute('ALTER TABLE resources_v2 RENAME TO resources')
        logging.info("Resources table migrated to v2")
    except sqlite3.OperationalError as e:
        logging.warning(f"Could not complete migration: {e}")



