"""Database initialization and constants for Lumina EduMesh Hub."""
import os
import sqlite3
import uuid
import time
import logging
import asyncio
from datetime import datetime

UPLOAD_DIR = "uploads"
DB_PATH = "data/hub.db"
PROFILE_ICONS_DIR = "profile_icons"
THUMBNAILS_DIR = "thumbnails"

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(PROFILE_ICONS_DIR, exist_ok=True)
os.makedirs(THUMBNAILS_DIR, exist_ok=True)


def gen_uid(prefix: str) -> str:
    """Generate a UID like GRD-a1b2c3d4 or SUBJ-e5f6g7h8."""
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


def gen_composite_uid(conn, grade: int, subject: str, prefix: str) -> str:
    """Generate a composite UID like GRD-xxxx-SUBJ-xxxx-8hex.

    Args:
        conn: SQLite connection.
        grade: Numeric grade (0=General, 9-12).
        subject: Subject name string.
        prefix: Item prefix (CRS or RES).
    """
    grade_uid = "GRD-00000000"
    row = conn.execute("SELECT id FROM grades WHERE name = ?", (f"Grade {grade}" if grade else "General",)).fetchone()
    if not row and grade:
        row = conn.execute("SELECT id FROM grades WHERE name LIKE ?", (f"%{grade}%",)).fetchone()
    if row:
        grade_uid = row[0]
    subject_uid = "SUBJ-00000000"
    row = conn.execute("SELECT id FROM subjects WHERE name = ?", (subject or "General",)).fetchone()
    if row:
        subject_uid = row[0]
    return f"{grade_uid}-{subject_uid}-{uuid.uuid4().hex[:8]}"

RETENTION_DELTAS = {
    "24h": 86400,
    "7d": 604800,
    "30d": 2592000,
    "3m": 7776000,
    "6m": 15552000,
}


def init_db():
    """Initialise the SQLite database schema and seed default data.

    Creates all tables idempotently (IF NOT EXISTS), runs composite indexes for
    hot query paths, seeds default grades/subjects, and creates a default admin
    account (username ``admin``, password ``lumina2026``) on first run.  Schema
    migrations are wrapped in try/except so they pass silently when columns or
    tables already exist.
    """
    from app.dependencies import hash_password

    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('PRAGMA busy_timeout=5000')
    conn.execute('PRAGMA cache_size=-8000')
    conn.execute('PRAGMA synchronous=NORMAL')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS scholars (id TEXT PRIMARY KEY, name TEXT UNIQUE, hashed_password TEXT, reset_required INTEGER DEFAULT 0, grade TEXT DEFAULT "", username TEXT)')
    c.execute('''CREATE TABLE IF NOT EXISTS resources (
        id TEXT PRIMARY KEY,
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
        superseded_by TEXT REFERENCES resources(id),
        topic_id TEXT DEFAULT '',
        file_path TEXT,
        type TEXT
    )''')
    c.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, hashed_password TEXT, name TEXT, department TEXT, scholar_id TEXT, reset_required INTEGER DEFAULT 0, role TEXT NOT NULL DEFAULT "teacher")')
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
    # ponytail: each index in its own try -- single try skips all on first failure
    for _idx_sql in [
        'CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token)',
        'CREATE INDEX IF NOT EXISTS idx_resources_status ON resources(status)',
        'CREATE INDEX IF NOT EXISTS idx_resources_subject ON resources(subject)',
        'CREATE INDEX IF NOT EXISTS idx_resources_grade ON resources(grade)',
        'CREATE INDEX IF NOT EXISTS idx_resources_type ON resources(resource_type)',
        'CREATE INDEX IF NOT EXISTS idx_downloads_scholar ON scholar_downloads(scholar_id)',
        'CREATE INDEX IF NOT EXISTS idx_subject_minutes_scholar ON subject_minutes(scholar_id)',
        'CREATE INDEX IF NOT EXISTS idx_study_sessions_scholar ON study_sessions(scholar_id)',
        'CREATE INDEX IF NOT EXISTS idx_weekly_study_scholar ON weekly_study(scholar_id)',
    ]:
        try:
            c.execute(_idx_sql)
        except Exception:
            pass
    c.execute('CREATE TABLE IF NOT EXISTS weekly_study (scholar_id TEXT PRIMARY KEY, total_seconds INTEGER DEFAULT 0, streak_days INTEGER DEFAULT 0, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    c.execute('CREATE TABLE IF NOT EXISTS activity_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (scholar_id) REFERENCES scholars(id))')
    c.execute('CREATE TABLE IF NOT EXISTS study_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, start_time DATETIME, end_time DATETIME, duration_seconds INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expiry TEXT, last_accessed DATETIME, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS subject_minutes (scholar_id TEXT NOT NULL, subject_name TEXT NOT NULL, minutes INTEGER DEFAULT 0, PRIMARY KEY (scholar_id, subject_name))')
    c.execute('CREATE TABLE IF NOT EXISTS refresh_tokens (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expires_at TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS persistent_keys (token TEXT PRIMARY KEY, username TEXT, role TEXT, used INTEGER DEFAULT 0, expires_at TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')

    c.execute('''CREATE TABLE IF NOT EXISTS courses (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      subject TEXT DEFAULT '',
      grade INTEGER DEFAULT 0,
      language TEXT DEFAULT 'en',
      cover_image TEXT DEFAULT '',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      published INTEGER DEFAULT 0,
      teacher_username TEXT DEFAULT '',
      enrollment_count INTEGER DEFAULT 0
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS course_resources (
      id TEXT PRIMARY KEY,
      course_id TEXT NOT NULL,
      topic_id TEXT DEFAULT '',
      resource_type TEXT NOT NULL DEFAULT 'textbook',
      title TEXT DEFAULT '',
      original_name TEXT DEFAULT '',
      filename TEXT DEFAULT '',
      file_size INTEGER DEFAULT 0,
      position INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS course_progress (
      student_id TEXT NOT NULL,
      course_id TEXT NOT NULL,
      current_position INTEGER DEFAULT 0,
      completed_count INTEGER DEFAULT 0,
      total_resources INTEGER DEFAULT 0,
      completed INTEGER DEFAULT 0,
      last_synced TEXT,
      enrolled_at TEXT DEFAULT (datetime('now')),
      PRIMARY KEY (student_id, course_id),
      FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS quiz_attempts (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      course_id TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      attempt_number INTEGER NOT NULL DEFAULT 1,
      score REAL DEFAULT 0,
      passed INTEGER DEFAULT 0,
      answers_json TEXT DEFAULT '',
      started_at TEXT,
      submitted_at TEXT DEFAULT (datetime('now')),
      time_taken_seconds INTEGER DEFAULT 0,
      quiz_version INTEGER DEFAULT 1,
      threshold_at_submission REAL DEFAULT 0.0,
      FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE,
      FOREIGN KEY (resource_id) REFERENCES course_resources(id) ON DELETE CASCADE
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS similar_courses (
      course_id TEXT NOT NULL,
      similar_course_id TEXT NOT NULL,
      created_by TEXT DEFAULT '',
      created_at TEXT DEFAULT (datetime('now')),
      PRIMARY KEY (course_id, similar_course_id),
      FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE,
      FOREIGN KEY (similar_course_id) REFERENCES courses(id) ON DELETE CASCADE
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS topics (
      id TEXT PRIMARY KEY,
      course_id TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
    )''')
    c.execute('''CREATE TABLE IF NOT EXISTS resource_topics (
      id TEXT PRIMARY KEY,
      subject TEXT NOT NULL,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      UNIQUE(subject, name)
    )''')
    c.execute('CREATE INDEX IF NOT EXISTS idx_course_resources_course_id ON course_resources(course_id)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_course_progress_student ON course_progress(student_id)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_quiz_attempts_student ON quiz_attempts(student_id)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_similar_courses_similar ON similar_courses(similar_course_id)')
    # ponytail: composite indexes for hot query paths
    c.execute('CREATE INDEX IF NOT EXISTS idx_resources_catalog ON resources(status, subject, grade, language, resource_type)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_study_sessions_scholar_start ON study_sessions(scholar_id, start_time)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token_used ON refresh_tokens(token, used, expires_at)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_persistent_keys_token_used ON persistent_keys(token, used, expires_at)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_scholar_downloads_resource ON scholar_downloads(resource_id)')

    c.execute('CREATE TABLE IF NOT EXISTS subjects (id TEXT PRIMARY KEY, name TEXT, symbol TEXT, class_name TEXT, UNIQUE(name, class_name))')

    try:
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_subjects_id ON subjects(id)')
    except Exception:
        pass

    c.execute('CREATE TABLE IF NOT EXISTS grades (id TEXT PRIMARY KEY, name TEXT UNIQUE)')
    c.execute('SELECT count(*) FROM grades')
    if c.fetchone()[0] == 0:
        for g in ["Grade 9", "Grade 10", "Grade 11", "Grade 12"]:
            c.execute("INSERT OR IGNORE INTO grades (id, name) VALUES (?, ?)", (f"GRD-{uuid.uuid4().hex[:8]}", g))

    c.execute('''CREATE TABLE IF NOT EXISTS zim_archives (
        id TEXT PRIMARY KEY,
        filename TEXT NOT NULL,
        title TEXT NOT NULL,
        article_count INTEGER DEFAULT 0,
        language TEXT DEFAULT 'en',
        uploaded_by INTEGER,
        uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        file_size INTEGER DEFAULT 0,
        zim_path TEXT DEFAULT ''
    )''')

    c.execute('''CREATE TABLE IF NOT EXISTS zim_articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        archive_id TEXT REFERENCES zim_archives(id) ON DELETE CASCADE,
        article_id TEXT NOT NULL,
        title TEXT NOT NULL,
        path TEXT NOT NULL,
        namespace TEXT DEFAULT 'A',
        has_thumbnail INTEGER DEFAULT 0
    )''')
    c.execute('CREATE INDEX IF NOT EXISTS idx_zim_articles_archive ON zim_articles(archive_id)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_zim_articles_title ON zim_articles(title)')

    try:
        default_pwd = hash_password("lumina2026")
        admin_id = f"LUMINA_01-T{uuid.uuid4().hex}"
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'admin')", ("admin", default_pwd, "Administrator", "System", admin_id))
        logging.info("=" * 50)
        logging.info("  DEFAULT ADMIN ACCOUNT CREATED")
        logging.info("  Change the password immediately via Dashboard > Settings")
        logging.info("=" * 50)
    except sqlite3.IntegrityError:
        pass

    # Do NOT force-reset admin password on every restart -- let admin keep their password

    c.execute('SELECT count(*) FROM subjects')
    if c.fetchone()[0] == 0:
        defaults = [
            (f"SUBJ-{uuid.uuid4().hex[:8]}", "Mathematics", "calculator", "All Classes"),
            (f"SUBJ-{uuid.uuid4().hex[:8]}", "Science", "atom", "All Classes"),
            (f"SUBJ-{uuid.uuid4().hex[:8]}", "History", "globe", "All Classes"),
            (f"SUBJ-{uuid.uuid4().hex[:8]}", "Literature", "book", "All Classes"),
            (f"SUBJ-{uuid.uuid4().hex[:8]}", "Computer Science", "laptop", "All Classes"),
            (f"SUBJ-{uuid.uuid4().hex[:8]}", "General", "folder", "All Classes"),
        ]
        c.executemany("INSERT INTO subjects (id, name, symbol, class_name) VALUES (?, ?, ?, ?)", defaults)

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
    c.execute('CREATE INDEX IF NOT EXISTS idx_topics_course_id ON topics(course_id)')
    c.execute('CREATE INDEX IF NOT EXISTS idx_course_resources_topic ON course_resources(topic_id)')
    conn.commit()
    conn.close()



