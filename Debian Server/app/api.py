# Fixed api.py for Lumina EduMesh Hub
from fastapi import FastAPI, UploadFile, File, Depends, HTTPException, status, Request, Response, Form, Query
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, StreamingResponse
import os
import subprocess
from .zim_auto_cleaner import start_zim_auto_cleaner
import sqlite3
import shutil
import logging
import uuid
import zipfile
import asyncio

async def get_zim_upload_max_size():
    try:
        _disk = await asyncio.to_thread(shutil.disk_usage, "/")
        return max(0, _disk.total - 1024 * 1024 * 1024)
    except Exception:
        return 5000 * 1024 * 1024


import re
import time
from pydantic import BaseModel, Field
from typing import List, Optional
import bcrypt as bcrypt_lib
from datetime import datetime, timedelta
from logging.handlers import RotatingFileHandler

# --- Logging ---
os.makedirs("data", exist_ok=True)
log_handler = RotatingFileHandler('data/hub.log', maxBytes=5*1024*1024, backupCount=3)
logging.basicConfig(handlers=[log_handler], level=logging.INFO, format='%(asctime)s - %(message)s')
# Admin‑action logger (tiny rotating file, ~2 MiB max, 3 backups)
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
    log_line = f"{now.isoformat()} - {username}: {action}\n"
    try:
        async with _admin_log_lock:
            with open("data/admin_actions.log", "a") as f:
                f.write(log_line)
    except Exception as e:
        logging.error(f"Could not write admin action log: {e}")

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
                async with _admin_log_lock:
                    with open("data/admin_actions.log", "w") as f:
                        f.writelines(kept_lines)
    except Exception as e:
        logging.error(f"Error pruning logs: {e}")

_startup_time = time.time()

app = FastAPI(title="Lumina EduMesh Hub")

@app.on_event("startup")
async def startup_services():
    start_zim_auto_cleaner(interval_seconds=3600)
    try:
        from app.discovery import MeshBeacon
        beacon = MeshBeacon(port=8000)
        beacon.start()
        app.state.beacon = beacon
    except Exception:
        pass

@app.on_event("shutdown")
async def shutdown_services():
    if hasattr(app.state, 'beacon'):
        try:
            app.state.beacon.stop()
        except Exception:
            pass

# Security
def hash_password(password: str) -> str:
    return bcrypt_lib.hashpw(password.encode(), bcrypt_lib.gensalt()).decode()

def verify_password(password: str, hashed: str) -> bool:
    return bcrypt_lib.checkpw(password.encode(), hashed.encode())

def validate_password_strength(password: str) -> tuple[bool, str]:
    if len(password) < 8:
        return False, "Password must be at least 8 characters"
    if not any(c.isupper() for c in password):
        return False, "Password must contain an uppercase letter"
    if not any(c.islower() for c in password):
        return False, "Password must contain a lowercase letter"
    if not any(c.isdigit() for c in password):
        return False, "Password must contain a digit"
    return True, ""
app.add_middleware(CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def start_pruning():
    async def prune_sessions():
        while True:
            await asyncio.sleep(3600)
            try:
                conn = sqlite3.connect(DB_PATH)
                conn.execute("DELETE FROM sessions WHERE last_accessed IS NOT NULL AND last_accessed < datetime('now', '-30 days')")
                conn.execute("DELETE FROM sessions WHERE last_accessed IS NULL AND created_at < datetime('now', '-30 days')")
                conn.commit()
                conn.close()
            except Exception:
                pass
    asyncio.create_task(prune_sessions())

# --- Anti‑Spam Rate Limiter ---
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.ip_records = {}
        self._lock = asyncio.Lock()
        asyncio.create_task(self.cleanup_stale())

    async def cleanup_stale(self):
        while True:
            await asyncio.sleep(60)
            async with self._lock:
                now = time.time()
                self.ip_records = {
                    ip: [t for t in ts if now - t < 60]
                    for ip, ts in self.ip_records.items()
                }

    async def dispatch(self, request: Request, call_next):
        client_ip = request.client.host if request.client else request.headers.get("X-Forwarded-For", "unknown")
        path = request.url.path
        async with self._lock:
            now = time.time()
            timestamps = self.ip_records.get(client_ip, [])
            timestamps = [t for t in timestamps if now - t < 60]

            strict_paths = ["/token", "/teacher", "/register", "/logout", "/student/token"]
            if any(path.startswith(p) for p in strict_paths):
                if len(timestamps) >= 50:
                    logging.warning(f"BLOCKED: Strict rate limit exceeded by IP {client_ip} on {path}")
                    return Response(content="Rate limit exceeded. Please wait 60 seconds.", status_code=429)

            if len(timestamps) >= 300:
                logging.warning(f"BLOCKED: General flood limit exceeded by IP {client_ip}")
                return Response(content="Too many requests. Please slow down.", status_code=429)

            timestamps.append(now)
            self.ip_records[client_ip] = timestamps
        return await call_next(request)

app.add_middleware(RateLimitMiddleware)

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Cache-Control"] = "no-cache, private"
    return response

# Paths
UPLOAD_DIR = "uploads"
DB_PATH = "data/hub.db"
PROFILE_ICONS_DIR = "profile_icons"
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(PROFILE_ICONS_DIR, exist_ok=True)

# Database Setup
def init_db():
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    conn.execute('PRAGMA journal_mode=WAL')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS scholars (id TEXT PRIMARY KEY, name TEXT UNIQUE)')
    c.execute('CREATE TABLE IF NOT EXISTS resources (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, file_path TEXT, type TEXT)')
    c.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, hashed_password TEXT, name TEXT, department TEXT, scholar_id TEXT, reset_required INTEGER DEFAULT 0, role TEXT NOT NULL DEFAULT "teacher")')
    # Existing columns added in newer schema – keep for backward compatibility
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
    # New role column (default teacher). Ignore if already present.
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
    except:
        pass
    try:
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_scholars_username ON scholars(username)')
    except:
        pass
    try:
        c.execute('CREATE INDEX IF NOT EXISTS idx_scholars_name ON scholars(name)')
    except:
        pass
    c.execute('CREATE TABLE IF NOT EXISTS activity_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, action TEXT, resource_id TEXT, metadata TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    c.execute('CREATE TABLE IF NOT EXISTS study_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, start_time DATETIME, end_time DATETIME, duration_seconds INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    try:
        c.execute('ALTER TABLE sessions ADD COLUMN role TEXT')
    except sqlite3.OperationalError:
        pass
    try:
        c.execute('ALTER TABLE sessions ADD COLUMN last_accessed DATETIME')
    except sqlite3.OperationalError:
        pass
    
    # Check subjects table cols to migrate to name + class_name primary key
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
    # Backfill IDs for existing subjects
    c.execute("SELECT rowid FROM subjects WHERE id IS NULL")
    for (rowid,) in c.fetchall():
        c.execute("UPDATE subjects SET id = ? WHERE rowid = ?", (f"SUBJ-{uuid.uuid4().hex[:8]}", rowid))
    try:
        c.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_subjects_id ON subjects(id)')
    except:
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
    except sqlite3.IntegrityError:
        pass
        
    # Populate default subjects if empty
    c.execute('SELECT count(*) FROM subjects')
    if c.fetchone()[0] == 0:
        defaults = [
            ("Mathematics", "calculator", "All Classes"),
            ("Science", "atom", "All Classes"),
            ("History", "globe", "All Classes"),
            ("Literature", "book", "All Classes"),
            ("Computer Science", "laptop", "All Classes"),
            ("General", "folder", "All Classes")
        ]
        c.executemany("INSERT INTO subjects (name, symbol, class_name) VALUES (?, ?, ?)", defaults)
        
    try:
        c.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)')
        c.execute('INSERT OR IGNORE INTO settings (key, value) VALUES ("log_retention", "30d")')
    except Exception as e:
        logging.error(f"Could not create settings table: {e}")

    try:
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    except sqlite3.OperationalError:
        pass
    conn.commit()
    conn.close()

init_db()
# Ensure admin has admin role (idempotent)
conn = sqlite3.connect(DB_PATH, timeout=5.0)
cur = conn.cursor()
cur.execute('UPDATE users SET role = "admin" WHERE username = "admin"')
conn.commit()
conn.close()

# Models
class TimeSync(BaseModel):
    current_time: str

class ScholarReg(BaseModel):
    username: str = Field(..., min_length=1, max_length=100)
    name: Optional[str] = Field(default=None, max_length=100)
    password: Optional[str] = Field(default="lumina2026", min_length=4, max_length=128)

class StudentLoginRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=100)
    password: str = Field(..., min_length=1, max_length=128)

class StudentChangePasswordRequest(BaseModel):
    scholar_id: Optional[str] = Field(default="", max_length=100)
    old_password: str = Field(..., max_length=128)
    new_password: str = Field(..., min_length=4, max_length=128)

class SubjectDeleteRequest(BaseModel):
    id: Optional[str] = Field(default=None, max_length=100)
    name: Optional[str] = Field(default=None, max_length=100)
    transfer_to: Optional[str] = Field(default=None, max_length=100)

class SyncActivity(BaseModel):
    action: str
    resource_id: str

class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str

class ForceChangePasswordRequest(BaseModel):
    new_password: str

class SubjectCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    symbol: str = Field(..., max_length=50)
    class_name: Optional[str] = Field(default="All Classes", max_length=100)

class TeacherCreate(BaseModel):
    username: str = Field(..., min_length=1, max_length=100)
    password: str = Field(..., min_length=4, max_length=128)
    name: Optional[str] = Field(default=None, max_length=100)
    department: Optional[str] = Field(default="General", max_length=100)

# Helper
def auto_register_if_new(scholar_id: str, name: str = "Roaming Scholar"):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT OR IGNORE INTO scholars (id, name) VALUES (?, ?)", (scholar_id, name))
    conn.commit()
    conn.close()

# Root redirect to welcome page (handles GET and HEAD)
@app.api_route("/", methods=["GET", "HEAD"])
async def root_redirect():
    return RedirectResponse(url="/dashboard")

# --- Auth Functions ---

def _extract_user(request: Request) -> dict:
    auth = request.headers.get("Authorization")
    cookie = request.cookies.get("lumina_session")
    if not cookie and not (auth and auth.startswith("Bearer ")):
        raise HTTPException(status_code=401, detail="Unauthorized: Session required.")
    token = cookie or (auth.removeprefix("Bearer ") if auth else "")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    cur = conn.cursor()
    cur.execute("SELECT s.username, s.role FROM sessions s JOIN users u ON s.username = u.username WHERE s.token = ?", (token,))
    row = cur.fetchone()
    if row:
        try:
            cur.execute("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
            conn.commit()
        except Exception:
            pass
        conn.close()
        return {"username": row[0], "role": row[1]}
    cur.execute("SELECT s.username, 'student' as role FROM sessions s JOIN scholars sc ON s.username = sc.id WHERE s.token = ?", (token,))
    row = cur.fetchone()
    if row:
        try:
            cur.execute("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
            conn.commit()
        except Exception:
            pass
        conn.close()
        return {"username": row[0], "role": "student"}
    conn.close()
    raise HTTPException(status_code=401, detail="Unauthorized: Invalid session.")

def verify_teacher(request: Request) -> str:
    user = _extract_user(request)
    if user["role"] not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teacher privilege required.")
    return user["username"]

def verify_admin(request: Request) -> str:
    user = _extract_user(request)
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Admin privilege required.")
    return user["username"]

def verify_student(request: Request):
    token = request.cookies.get("lumina_session") or request.headers.get("Authorization", "").removeprefix("Bearer ")
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    cur = conn.cursor()
    cur.execute("SELECT username FROM sessions WHERE token = ? AND role = 'student'", (token,))
    row = cur.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=401, detail="Invalid or expired student session")
    try:
        cur.execute("UPDATE sessions SET last_accessed = datetime('now') WHERE token = ?", (token,))
        conn.commit()
    except Exception:
        pass
    # Also verify scholar still exists
    cur.execute("SELECT id FROM scholars WHERE id = ?", (row[0],))
    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=401, detail="Account no longer exists.")
    conn.close()
    return row[0]

# --- Endpoints ---

@app.get("/api/health")
async def health():
    return {"status": "ok", "uptime": time.time() - _startup_time}

@app.get("/ping")
async def ping_server():
    return {"status": "pong"}

@app.get("/api/files")
async def list_files(teacher_user: str = Depends(verify_teacher)):   
    if not os.path.exists(UPLOAD_DIR):
        return []
    files = []
    for f in os.listdir(UPLOAD_DIR):
        fp = os.path.join(UPLOAD_DIR, f)
        if os.path.isfile(fp):
            files.append({"name": f, "size": os.path.getsize(fp)})
    return files

@app.get("/system/stats")
async def system_stats(teacher_user: str = Depends(verify_teacher)):
    return {"status": "healthy"}

@app.post("/system/sync-time")
async def sync_time(data: TimeSync, admin_user: str = Depends(verify_admin)):
    try:
        if not data.current_time or len(data.current_time) >= 64:
            return {"status": "failed"}
        if not re.match(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$', data.current_time):
            return {"status": "failed"}
        proc = await asyncio.create_subprocess_exec(
            "date", "-s", data.current_time,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        result = subprocess.CompletedProcess(args=["date", "-s", data.current_time], returncode=proc.returncode, stdout=stdout, stderr=stderr)
        logging.info(f"Time Synced: {data.current_time}")
        return {"status": "ok"}
    except Exception:
        return {"status": "failed"}

# Captive portal helper
@app.get("/generate_204")
async def generate_204():
    """Tricks Android into thinking it has internet so it doesn't switch to cellular."""
    return Response(status_code=204)

# Sync activity
@app.post("/sync/activity")
async def sync_activity(data: SyncActivity, student_id: str = Depends(verify_student)):
    auto_register_if_new(student_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO activity_logs (scholar_id, action, resource_id) VALUES (?, ?, ?)", (student_id, data.action, data.resource_id))
    conn.commit()
    conn.close()
    return {"status": "synced"}

# Sync downloads
@app.post("/sync/downloads")
async def sync_downloads(resource_ids: List[str], student_id: str = Depends(verify_student)):
    auto_register_if_new(student_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    for rid in resource_ids:
        c.execute("INSERT OR IGNORE INTO scholar_downloads (scholar_id, resource_id) VALUES (?, ?)", (student_id, rid))
    conn.commit()
    conn.close()
    return {"status": "ok"}

# Restore profile
@app.get("/sync/restore")
async def restore_profile(student_id: str = Depends(verify_student)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT action, resource_id, timestamp FROM activity_logs WHERE scholar_id = ? ORDER BY timestamp DESC LIMIT 10", (student_id,))
    recent = [{"action": r[0], "resource_id": r[1], "time": r[2]} for r in c.fetchall()]
    c.execute("SELECT resource_id FROM scholar_downloads WHERE scholar_id = ?", (student_id,))
    downloads = [r[0] for r in c.fetchall()]
    conn.close()
    return {"recent_activity": recent, "download_history": downloads}

# ---- Student Activity & Analytics API ----

class ActivityLog(BaseModel):
    action: str = Field(..., max_length=255)
    resource_id: str = Field(default="", max_length=255)
    metadata: str = Field(default="", max_length=255)

@app.post("/student/activity")
async def log_activity(data: ActivityLog, student_id: str = Depends(verify_student)):
    auto_register_if_new(student_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO activity_logs (scholar_id, action, resource_id, metadata) VALUES (?, ?, ?, ?)",
              (student_id, data.action, data.resource_id, data.metadata))
    conn.commit()
    conn.close()
    return {"status": "ok"}

@app.get("/student/activity")
async def get_activity(student_id: str = Depends(verify_student), limit: int = Query(default=25, ge=1, le=1000), offset: int = Query(default=0, ge=0)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT rowid AS id, action, resource_id, metadata, timestamp FROM activity_logs WHERE scholar_id = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?",
              (student_id, limit, offset))
    rows = c.fetchall()
    conn.close()
    return [{"id": r[0], "action": r[1], "resource_id": r[2], "metadata": r[3], "timestamp": r[4]} for r in rows]

class StudyEnd(BaseModel):
    session_id: int
    duration_seconds: int

@app.post("/student/study/start")
async def start_study_session(student_id: str = Depends(verify_student)):
    auto_register_if_new(student_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO study_sessions (scholar_id, start_time) VALUES (?, datetime('now'))",
              (student_id,))
    session_id = c.lastrowid
    conn.commit()
    conn.close()
    return {"status": "ok", "session_id": session_id}

@app.post("/student/study/end")
async def end_study_session(data: StudyEnd, student_id: str = Depends(verify_student)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("UPDATE study_sessions SET end_time = datetime('now'), duration_seconds = ? WHERE id = ? AND scholar_id = ?",
              (data.duration_seconds, data.session_id, student_id))
    conn.commit()
    conn.close()
    return {"status": "ok"}

@app.get("/student/analytics")
async def get_analytics(student_id: str = Depends(verify_student)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    # Total study minutes today
    c.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM study_sessions WHERE scholar_id = ? AND date(start_time) = date('now')", (student_id,))
    today_secs = c.fetchone()[0]
    # Total study minutes this week (ISO week)
    c.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM study_sessions WHERE scholar_id = ? AND start_time >= datetime('now', '-7 days')", (student_id,))
    week_secs = c.fetchone()[0]
    # Total study minutes this month
    c.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM study_sessions WHERE scholar_id = ? AND strftime('%Y-%m', start_time) = strftime('%Y-%m', 'now')", (student_id,))
    month_secs = c.fetchone()[0]
    # Subject breakdown from activity logs (views by action)
    c.execute("SELECT metadata, COUNT(*) as cnt FROM activity_logs WHERE scholar_id = ? AND action = 'view' AND metadata != '' GROUP BY metadata ORDER BY cnt DESC", (student_id,))
    subject_rows = c.fetchall()
    # Streak: count consecutive days with activity
    c.execute("SELECT DISTINCT date(timestamp) as d FROM activity_logs WHERE scholar_id = ? ORDER BY d DESC", (student_id,))
    active_days = [r[0] for r in c.fetchall()]
    streak = 0
    today = datetime.now().date()
    for i, d in enumerate(active_days):
        expected = today - timedelta(days=i)
        if datetime.strptime(d, "%Y-%m-%d").date() == expected:
            streak += 1
        else:
            break
    # Total resources saved
    c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE scholar_id = ?", (student_id,))
    saved = c.fetchone()[0]
    conn.close()
    return {
        "study_minutes_today": today_secs // 60,
        "study_minutes_this_week": week_secs // 60,
        "study_minutes_this_month": month_secs // 60,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": [{"name": r[0], "minutes": r[1] * 5} for r in subject_rows]
    }

import base64

class ProfileUpdate(BaseModel):
    name: Optional[str] = Field(default=None, max_length=100)
    grade: Optional[str] = Field(default=None, max_length=50)

@app.post("/student/profile/update")
async def update_student_profile(data: dict, student_id: str = Depends(verify_student)):
    name = data.get("name")
    grade = data.get("grade")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        if name:
            c.execute("UPDATE scholars SET name = ? WHERE id = ?", (name.strip(), student_id))
        if grade is not None:
            c.execute("UPDATE scholars SET grade = ? WHERE id = ?", (grade.strip(), student_id))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=400, detail="Failed to update profile.")
    finally:
        conn.close()

class IconUpload(BaseModel):
    image_data: str
    image_ext: str = "png"

@app.post("/student/profile/icon")
async def upload_profile_icon(data: IconUpload, student_id: str = Depends(verify_student)):
    try:
        raw = base64.b64decode(data.image_data)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data.")
    if len(raw) > 500 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 500KB)")
    ext = data.image_ext.replace(".", "")
    ALLOWED_MAGIC = {
        b'\x89PNG\r\n\x1a\n': 'png',
        b'\xff\xd8\xff': 'jpg',
        b'GIF89a': 'gif',
        b'GIF87a': 'gif',
        b'RIFF': 'webp',
    }
    if ext.lower() == 'jpeg':
        ext = 'jpg'
    is_valid = False
    for magic, fmt in ALLOWED_MAGIC.items():
        if raw[:len(magic)] == magic:
            if fmt == ext.lower():
                is_valid = True
                break
    if not is_valid:
        raise HTTPException(status_code=400, detail="Invalid image format")
    if ext not in ("png", "jpg", "jpeg", "gif", "webp"):
        ext = "png"
    safe_id = re.sub(r'[^A-Za-z0-9_-]', '_', student_id)
    filename = f"{safe_id}_icon.{ext}"
    filepath = os.path.join(PROFILE_ICONS_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(raw)
    return {"status": "ok", "filename": filename}

@app.get("/student/profile/icon/{scholar_id}")
async def get_profile_icon(scholar_id: str):
    safe_id = re.sub(r'[^A-Za-z0-9_-]', '_', scholar_id)
    for ext in ("png", "jpg", "jpeg", "gif", "webp"):
        path = os.path.join(PROFILE_ICONS_DIR, f"{safe_id}_icon.{ext}")
        if os.path.exists(path):
            return FileResponse(path, media_type=f"image/{ext}")
    raise HTTPException(status_code=404, detail="No profile icon found.")

# Register scholar
@app.post("/register")
async def register_scholar(scholar: ScholarReg, request: Request):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        display_name = scholar.name or scholar.username
        c.execute("SELECT id FROM scholars WHERE username = ?", (scholar.username,))
        existing = c.fetchone()
        if existing:
            full_id = existing[0]
        else:
            unique_suffix = uuid.uuid4().hex
            full_id = f"LUMINA_01-{unique_suffix}"

        pwd = scholar.password or "lumina2026"
        if scholar.password:
            valid, msg = validate_password_strength(pwd)
            if not valid:
                raise HTTPException(status_code=400, detail=msg)
        hashed = hash_password(pwd)

        if existing:
            c.execute("UPDATE scholars SET hashed_password = ?, name = ?, reset_required = 0 WHERE id = ?", (hashed, display_name, full_id))
        else:
            c.execute("INSERT INTO scholars (id, username, name, hashed_password, reset_required) VALUES (?, ?, ?, ?, 0)", (full_id, scholar.username, display_name, hashed))

        token = f"LUMINA_HUB-{uuid.uuid4().hex}"
        c.execute("INSERT INTO sessions (token, username, role) VALUES (?, ?, 'student')", (token, full_id))
        conn.commit()
        response = JSONResponse({"id": full_id, "token": token})
        response.set_cookie(key="lumina_session", value=token, httponly=True, samesite="strict", secure=request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https", max_age=86400)
        return response
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] register_scholar: {e}")
        raise HTTPException(status_code=400, detail="Registration failed")
    finally:
        conn.close()

# Student Token / Login
@app.post("/student/token")
async def student_login(data: StudentLoginRequest, request: Request):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT id, hashed_password, reset_required FROM scholars WHERE username = ?", (data.username,))
        row = c.fetchone()
        
        if not row:
            raise HTTPException(status_code=401, detail="Student account not found.")
        
        scholar_id, hashed_pwd, reset_req = row

        pwd_to_check = hashed_pwd
        if not pwd_to_check:
            raise HTTPException(status_code=401, detail="Password not set. Contact teacher to set your password.")

        if not verify_password(data.password, pwd_to_check):
            raise HTTPException(status_code=401, detail="Invalid student credentials.")
        
        token = f"LUMINA_HUB-{uuid.uuid4().hex}"
        c.execute("INSERT INTO sessions (token, username, role) VALUES (?, ?, 'student')", (token, scholar_id))
        conn.commit()
        
        c.execute("SELECT name, grade FROM scholars WHERE id = ?", (scholar_id,))
        srow = c.fetchone()
        srow_name = srow[0] if srow else data.username
        srow_grade = srow[1] if srow else ""
        
        response = JSONResponse({"status": "ok", "scholar_id": scholar_id, "token": token, "name": srow_name, "grade": srow_grade, "reset_required": bool(reset_req)})
        response.set_cookie(key="lumina_session", value=token, httponly=True, samesite="strict", max_age=86400, secure=request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https")
        return response
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] student_login: {e}")
        raise HTTPException(status_code=500, detail="Login failed")
    finally:
        conn.close()

# Student Password Change
@app.post("/student/change-password")
async def student_change_password(data: StudentChangePasswordRequest, student_id: str = Depends(verify_student)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT hashed_password FROM scholars WHERE id = ?", (student_id,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=400, detail="Password not set. Contact your teacher.")
        if not row[0]:
            raise HTTPException(status_code=400, detail="Password not set. Contact your teacher.")
        if not verify_password(data.old_password, row[0]):
            raise HTTPException(status_code=400, detail="Incorrect current password.")
        hashed = hash_password(data.new_password)
        c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 0 WHERE id = ?", (hashed, student_id))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] student_change_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to change password")
    finally:
        conn.close()

# Subjects API
@app.get("/subjects")
async def get_subjects(teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT id, name, symbol, class_name FROM subjects ORDER BY class_name ASC, name ASC")
        rows = c.fetchall()
        return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": r[3] or "All Classes"} for r in rows]
    except sqlite3.OperationalError:
        c.execute("SELECT id, name, symbol FROM subjects ORDER BY name ASC")
        rows = c.fetchall()
        return [{"id": r[0], "name": r[1], "symbol": r[2], "class_name": "All Classes"} for r in rows]
    finally:
        conn.close()

# Teacher Profile Management API
@app.post("/teacher/subjects")
async def create_subject(subject: SubjectCreate, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        class_val = subject.class_name or "All Classes"
        subj_id = f"SUBJ-{uuid.uuid4().hex[:8]}"
        c.execute("INSERT INTO subjects (id, name, symbol, class_name) VALUES (?, ?, ?, ?)", (subj_id, subject.name, subject.symbol, class_val))
        conn.commit()
        return {"status": "success", "id": subj_id, "name": subject.name, "symbol": subject.symbol, "class_name": class_val}
    except Exception as e:
        print(f"[ERROR] create_subject: {e}")
        raise HTTPException(status_code=400, detail="Failed to create subject")
    finally:
        conn.close()

@app.get("/teachers")
async def get_teachers(teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT username, name, department, reset_required FROM users WHERE username != 'admin' ORDER BY name ASC")
        rows = c.fetchall()
    except sqlite3.OperationalError:
        c.execute("SELECT username, name, department FROM users WHERE username != 'admin' ORDER BY name ASC")
        rows = [(*r, 0) for r in c.fetchall()]
    conn.close()
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "General", "reset_required": r[3] or 0} for r in rows]

@app.get("/teacher/me")
async def get_teacher_me(teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT name, department, scholar_id, reset_required FROM users WHERE username = ?", (teacher_user,))
    row = c.fetchone()
    conn.close()
    if row:
        reset_val = row[3] or 0
        if teacher_user == "admin":
            reset_val = 0
        return {"username": teacher_user, "name": row[0] or teacher_user, "department": row[1] or "General", "scholar_id": row[2], "reset_required": reset_val}
    return {"username": teacher_user, "reset_required": 0}

@app.post("/teacher/profiles")
async def create_teacher_profile(teacher: TeacherCreate, admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT username FROM users WHERE username = ?", (teacher.username,))
    if c.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="Username already exists.")
    
    display_name = teacher.name or teacher.username
    dept = teacher.department or "General"
    
    unique_suffix = uuid.uuid4().hex
    full_id = f"LUMINA_01-T{unique_suffix}"
    c.execute("INSERT OR IGNORE INTO scholars (id, name) VALUES (?, ?)", (full_id, display_name))
    
    hashed_pwd = hash_password(teacher.password)
    try:
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id) VALUES (?, ?, ?, ?, ?)", (teacher.username, hashed_pwd, display_name, dept, full_id))
        conn.commit()
        return {"status": "success", "username": teacher.username, "name": display_name, "department": dept, "scholar_id": full_id}
    except Exception as e:
        print(f"[ERROR] create_teacher_profile: {e}")
        raise HTTPException(status_code=400, detail="Failed to create teacher profile")
    finally:
        conn.close()

@app.delete("/teacher/profiles/{username}")
async def delete_teacher_profile(username: str, admin_user: str = Depends(verify_admin)):
    if username == 'admin':
        raise HTTPException(status_code=400, detail="Cannot delete admin account.")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("DELETE FROM users WHERE username = ?", (username,))
    conn.commit()
    conn.close()
    return {"status": "success"}

# Teacher API examples
@app.get("/teacher/scholars")
async def get_scholars(teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT id, name, reset_required FROM scholars ORDER BY name ASC")
        rows = c.fetchall()
    except sqlite3.OperationalError:
        c.execute("SELECT id, name FROM scholars ORDER BY name ASC")
        rows = [(*r, 0) for r in c.fetchall()]
    conn.close()
    return [{"id": r[0], "name": r[1], "reset_required": r[2] or 0} for r in rows]

@app.get("/api/limits")
async def get_limits(teacher_user: str = Depends(verify_teacher)):
    return {"zim_upload_max_size": await get_zim_upload_max_size()}

@app.get("/stats")
async def get_stats(teacher_user: str = Depends(verify_teacher)):
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    battery_percent = 100
    try:
        if os.path.exists("/sys/class/power_supply/BAT0/capacity"):
            with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
                battery_percent = int(f.read().strip())
    except Exception:
        pass
    return {"storage_percent": (used / total) * 100, "battery_percent": battery_percent}

@app.get("/resources")
@app.get("/api/catalog")
async def list_resources():
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT id, title, file_path, type, subject, grade FROM resources")
    except sqlite3.OperationalError:
        try:
            c.execute("SELECT id, title, file_path, type, subject, '' as grade FROM resources")
        except sqlite3.OperationalError:
            c.execute("SELECT id, title, file_path, type, 'General' as subject, '' as grade FROM resources")
    rows = c.fetchall()
    conn.close()
    result = []
    for r in rows:
        fpath = r[2]
        mtime = 0.0
        try:
            mtime = os.path.getmtime(fpath)
        except OSError:
            mtime = 0.0
        result.append({
            "id": r[0], "title": r[1],
            "pdfUrl": f"/files/{os.path.basename(fpath)}",
            "type": r[3], "subject": r[4] or "General",
            "grade": r[5] or "", "mtime": mtime,
        })
    return result

@app.post("/teacher/upload")
async def upload_resource(title: str, type: str, subject: str = "General", grade: str = "", file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher), request: Request = None):
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    free_gb = free // (2**30)
    if free_gb < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'unnamed_file')
    file_path = os.path.join(UPLOAD_DIR, safe_filename)
    contents = await file.read()
    if await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")
    if len(contents) > 100 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
    with open(file_path, "wb") as buffer:
        buffer.write(contents)
    await file.close()
    try:
        c.execute("INSERT INTO resources (title, file_path, type, subject, grade) VALUES (?, ?, ?, ?, ?)", (title, file_path, type, subject, grade))
    except sqlite3.OperationalError:
        try:
            c.execute("INSERT INTO resources (title, file_path, type, subject) VALUES (?, ?, ?, ?)", (title, file_path, type, subject))
        except sqlite3.OperationalError:
            c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)", (title, file_path, type))
    conn.commit()
    conn.close()
    return {"status": "success"}
@app.post("/teacher/upload-zim")
async def upload_zim(
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher),
    request: Request = None
):
    # Storage space check (minimum 2 GB free)
    total, used, free = await asyncio.to_thread(shutil.disk_usage, "/")
    free_gb = free // (2**30)
    if free_gb < 2:
        raise HTTPException(status_code=507, detail="Insufficient storage space for ZIM upload.")
    contents = await file.read()
    if await request.is_disconnected():
        raise HTTPException(status_code=499, detail="Client disconnected")
    if len(contents) > await get_zim_upload_max_size():
        raise HTTPException(
            status_code=413,
            detail=f"ZIM upload exceeds maximum size limit of {await get_zim_upload_max_size() // (1024 * 1024)} MiB."
        )
    if not file.filename:
        raise HTTPException(status_code=400, detail="Uploaded file has no filename.")

    # Write to temporary directory
    tmp_dir = os.path.join(UPLOAD_DIR, f"tmp_{uuid.uuid4().hex}")
    os.makedirs(tmp_dir, exist_ok=True)
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'archive.zip')
    archive_path = os.path.join(tmp_dir, safe_filename)
    with open(archive_path, "wb") as f:
        f.write(contents)
    # Extract archive (ZIP compatible)
    try:
        with zipfile.ZipFile(archive_path, "r") as zip_ref:
            for entry in zip_ref.namelist():
                if '..' in entry or entry.startswith('/'):
                    raise HTTPException(status_code=400, detail="ZIP contains invalid path entries.")
            zip_ref.extractall(tmp_dir)
        imported = []
        zim_target_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "zim_pages")
        os.makedirs(zim_target_dir, exist_ok=True)
        for root, _, files in os.walk(tmp_dir):
            if await request.is_disconnected():
                raise HTTPException(status_code=499, detail="Client disconnected")
            for fname in files:
                if not fname.lower().endswith('.html'):
                    continue
                src = os.path.join(root, fname)
                if "__" not in fname:
                    article_id = uuid.uuid4().hex[:8].upper()
                    title = os.path.splitext(fname)[0]
                    dest_name = f"{article_id}__{title}.html"
                else:
                    dest_name = fname
                dest_path = os.path.join(zim_target_dir, dest_name)
                shutil.move(src, dest_path)
                imported.append(dest_name)
        return {"status": "success", "imported": imported}
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Invalid ZIM/ZIP archive.")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Failed to extract archive.")
    finally:
        if os.path.exists(tmp_dir):
            shutil.rmtree(tmp_dir, ignore_errors=True)
@app.post("/teacher/import-server-file")
async def import_server_file(filename: str, title: str, type: str, subject: str = "General", teacher_user: str = Depends(verify_teacher)):
    if '..' in filename or '/' in filename or '\\' in filename:
        raise HTTPException(status_code=400, detail="Invalid filename.")
    file_path = os.path.join(UPLOAD_DIR, os.path.basename(filename))
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found on server.")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
    try:
        c.execute("INSERT INTO resources (title, file_path, type, subject) VALUES (?, ?, ?, ?)", (title, file_path, type, subject))
    except sqlite3.OperationalError:
        c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)", (title, file_path, type))
    conn.commit()
    conn.close()
    return {"status": "success"}

@app.post("/token")
async def login(response: Response, request: Request, username: str = Form(...), password: str = Form(...)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT hashed_password, name, department, scholar_id, reset_required, role FROM users WHERE username = ?", (username,))
        row = c.fetchone()
        reset_req = row[4] if row else 0
        if username == "admin":
            reset_req = 0
    except sqlite3.OperationalError:
        c.execute("SELECT hashed_password, username as name, 'General' as department, scholar_id FROM users WHERE username = ?", (username,))
        row = c.fetchone()
        if row and not row[3]:
            fallback_id = f"LUMINA_01-T{uuid.uuid4().hex}"
            conn2 = sqlite3.connect(DB_PATH, timeout=5.0)
            conn2.execute("UPDATE users SET scholar_id = ? WHERE username = ?", (fallback_id, username))
            conn2.commit()
            conn2.close()
            row = (row[0], row[1], row[2], fallback_id)
        reset_req = 0
    conn.close()
    if not row:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")
    if row[0] == 'DISABLED':
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="This account has been disabled by an administrator.")
    if not verify_password(password, row[0]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")
    
    user_role = row[5] if (row and len(row) > 5) else ("admin" if username == "admin" else "teacher")
    session_token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO sessions (token, username, role) VALUES (?, ?, ?)", (session_token, username, user_role))
    conn.commit()
    conn.close()
    scholar_id = row[3] if (row and row[3]) else None
    if not scholar_id:
        scholar_id = f"LUMINA_01-T{uuid.uuid4().hex}"
        conn2 = sqlite3.connect(DB_PATH, timeout=5.0)
        conn2.execute("UPDATE users SET scholar_id = ? WHERE username = ?", (scholar_id, username))
        conn2.commit()
        conn2.close()
    response.set_cookie(key="lumina_session", value=session_token, httponly=True, max_age=86400, samesite="strict", secure=request.url.scheme == "https" or request.headers.get("x-forwarded-proto", "") == "https")
    return {
        "access_token": session_token,
        "token_type": "bearer",
        "username": username,
        "name": row[1] or username,
        "department": row[2] or "General",
        "scholar_id": scholar_id,
        "role": user_role,
        "reset_required": reset_req or 0
    }

@app.get("/logout")
@app.post("/logout")
async def logout(request: Request, response: Response):
    token = request.cookies.get("lumina_session")
    if token:
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        cur = conn.cursor()
        cur.execute("DELETE FROM sessions WHERE token = ?", (token,))
        conn.commit()
        conn.close()
    response.delete_cookie(key="lumina_session", path="/")
    return RedirectResponse(url="/welcome")

@app.post("/teacher/change-password")
async def change_password(data: ChangePasswordRequest, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT hashed_password FROM users WHERE username = ?", (teacher_user,))
    row = c.fetchone()
    if not row or not verify_password(data.old_password, row[0]):
        conn.close()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Incorrect current password.")
    valid, msg = validate_password_strength(data.new_password)
    if not valid:
        conn.close()
        raise HTTPException(status_code=400, detail=msg)
    new_hash = hash_password(data.new_password)
    c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
    conn.commit()
    conn.close()
    return {"status": "success"}

@app.post("/teacher/disable-default-admin")
async def disable_default_admin(admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT count(*) FROM users WHERE username != 'admin'")
    count = c.fetchone()[0]
    if count == 0:
        conn.close()
        raise HTTPException(status_code=400, detail="Cannot disable default admin: No teacher profiles exist.")
    c.execute("UPDATE users SET hashed_password = 'DISABLED' WHERE username = 'admin'")
    conn.commit()
    conn.close()
    await log_admin_action(admin_user, "disabled the default admin account")
    return {"status": "success"}

@app.post("/teacher/enable-default-admin")
async def enable_default_admin(admin_user: str = Depends(verify_admin)):
    hashed = hash_password("lumina2026")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("UPDATE users SET hashed_password = ? WHERE username = 'admin'", (hashed,))
    conn.commit()
    conn.close()
    await log_admin_action(admin_user, "enabled the default admin account")
    return {"status": "success"}

@app.get("/teacher/default-admin-status")
async def default_admin_status(admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT hashed_password FROM users WHERE username = 'admin'")
    row = c.fetchone()
    conn.close()
    if row and row[0] == 'DISABLED':
        return {"enabled": False}
    return {"enabled": True}

# Danger Zone Endpoints
@app.post("/teacher/scholars/reset-password/{scholar_id}")
async def teacher_reset_student_password(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        hashed = hash_password("lumina2026")
        c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 1 WHERE id = ?", (hashed, scholar_id))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] teacher_reset_student_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to reset password")
    finally:
        conn.close()

@app.delete("/teacher/scholars/{scholar_id}")
async def teacher_delete_student(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("DELETE FROM scholars WHERE id = ?", (scholar_id,))
        c.execute("DELETE FROM activity_logs WHERE scholar_id = ?", (scholar_id,))
        c.execute("DELETE FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] teacher_delete_student: {e}")
        raise HTTPException(status_code=400, detail="Failed to delete student")
    finally:
        conn.close()

@app.post("/teacher/force-change-password")
async def force_change_password(data: ForceChangePasswordRequest, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT reset_required FROM users WHERE username = ?", (teacher_user,))
        row = c.fetchone()
        if not row or not row[0]:
            conn.close()
            raise HTTPException(status_code=400, detail="Password reset not required.")
        valid, msg = validate_password_strength(data.new_password)
        if not valid:
            conn.close()
            raise HTTPException(status_code=400, detail=msg)
        new_hash = hash_password(data.new_password)
        c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, teacher_user))
        conn.commit()
        return {"status": "success"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] force_change_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to change password")
    finally:
        conn.close()

@app.post("/teacher/reset-password/{username}")
async def force_reset_teacher_password(username: str, admin_user: str = Depends(verify_admin)):
    if username == "admin":
        raise HTTPException(status_code=400, detail="Cannot reset the default admin password. Use the Settings page to re-enable the default admin account.")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        hashed = hash_password("lumina2026")
        c.execute("UPDATE users SET hashed_password = ?, reset_required = 1 WHERE username = ?", (hashed, username))
        conn.commit()
        await log_admin_action(admin_user, f"reset password for teacher {username}")
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] force_reset_teacher_password: {e}")
        raise HTTPException(status_code=400, detail="Failed to reset password")
    finally:
        conn.close()

@app.post("/teacher/subjects/delete")
async def delete_subject(data: SubjectDeleteRequest, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        # Look up by ID first, fall back to name
        if data.id:
            c.execute("SELECT name FROM subjects WHERE id = ?", (data.id,))
        else:
            c.execute("SELECT name FROM subjects WHERE name = ?", (data.name,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Subject not found.")
        subject_name = row[0]
            
        if data.transfer_to:
            c.execute("SELECT COUNT(*) FROM subjects WHERE name = ?", (data.transfer_to,))
            if c.fetchone()[0] == 0:
                raise HTTPException(status_code=400, detail="Target subject does not exist.")
            c.execute("UPDATE resources SET subject = ? WHERE subject = ?", (data.transfer_to, subject_name))
        else:
            c.execute("SELECT file_path FROM resources WHERE subject = ?", (subject_name,))
            files = [r[0] for r in c.fetchall()]
            for fp in files:
                if os.path.exists(fp):
                    try:
                        os.remove(fp)
                    except Exception as e:
                        logging.warning(f"Could not remove physical file {fp}: {e}")
            c.execute("DELETE FROM resources WHERE subject = ?", (subject_name,))
            
        if data.id:
            c.execute("DELETE FROM subjects WHERE id = ?", (data.id,))
        else:
            c.execute("DELETE FROM subjects WHERE name = ?", (data.name,))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] delete_subject: {e}")
        raise HTTPException(status_code=400, detail="Failed to delete subject")
    finally:
        conn.close()

# --- Grades API ---
@app.get("/grades")
async def get_grades(teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT name FROM grades ORDER BY name ASC")
    rows = c.fetchall()
    conn.close()
    return [{"name": r[0]} for r in rows]

@app.post("/grades")
async def create_grade(data: dict, teacher_user: str = Depends(verify_teacher)):
    name = data.get("name", "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Grade name is required.")
    if len(name) > 50:
        raise HTTPException(status_code=400, detail="Grade name too long (max 50 characters).")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("INSERT INTO grades (name) VALUES (?)", (name,))
        conn.commit()
        return {"status": "success", "name": name}
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=400, detail="Grade already exists.")
    finally:
        conn.close()

@app.delete("/grades/{name}")
async def delete_grade(name: str, transfer_to: str = None, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    if transfer_to:
        c.execute("SELECT COUNT(*) FROM grades WHERE name = ?", (transfer_to,))
        if c.fetchone()[0] == 0:
            raise HTTPException(status_code=400, detail="Target grade does not exist.")
        c.execute("UPDATE resources SET grade = ? WHERE grade = ?", (transfer_to, name))
    else:
        c.execute("SELECT file_path FROM resources WHERE grade = ?", (name,))
        files = c.fetchall()
        for (fp,) in files:
            if os.path.exists(fp):
                os.remove(fp)
        c.execute("DELETE FROM resources WHERE grade = ?", (name,))
    c.execute("DELETE FROM grades WHERE name = ?", (name,))
    conn.commit()
    conn.close()
    return {"status": "success"}

@app.delete("/teacher/resources/{resource_id}")
async def delete_resource(resource_id: int, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT file_path FROM resources WHERE id = ?", (resource_id,))
        row = c.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Resource not found.")
        file_path = row[0]
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                logging.warning(f"Could not remove physical file {file_path}: {e}")
        c.execute("DELETE FROM resources WHERE id = ?", (resource_id,))
        c.execute("DELETE FROM scholar_downloads WHERE resource_id = ?", (str(resource_id),))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] delete_resource: {e}")
        raise HTTPException(status_code=400, detail="Failed to delete resource")
    finally:
        conn.close()

@app.get("/api/stream/{filename:path}")
async def stream_file(filename: str, request: Request):
    file_path = os.path.join(UPLOAD_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    file_size = os.path.getsize(file_path)
    range_header = request.headers.get("range")
    if range_header:
        start_str, _, end_str = range_header.replace("bytes=", "").partition("-")
        start = int(start_str) if start_str else 0
        end = int(end_str) if end_str else file_size - 1
        if start >= file_size:
            raise HTTPException(status_code=416, detail="Range not satisfiable")
        content_length = end - start + 1
        async def _stream_chunk():
            with open(file_path, "rb") as f:
                f.seek(start)
                remaining = content_length
                while remaining > 0:
                    chunk = f.read(min(65536, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk
        return StreamingResponse(
            _stream_chunk(),
            status_code=206,
            media_type="application/octet-stream",
            headers={
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(content_length),
                "Accept-Ranges": "bytes",
            }
        )
    return FileResponse(file_path, headers={"Accept-Ranges": "bytes"})

THUMBNAILS_DIR = "thumbnails"
os.makedirs(THUMBNAILS_DIR, exist_ok=True)

def _find_video_thumb_time(file_path: str, max_search: int = 30) -> float:
    """Determine a thumbnail time offset that avoids black intro frames.

    Uses ffmpeg's blackdetect filter to find black segments in the video,
    then returns 1 second after the last detected black segment ends. If no
    black is detected or ffmpeg fails, falls back to 2 seconds.

    Args:
        file_path: Path to the video file on disk.
        max_search: Maximum time in seconds to consider (default 30). The
            result is clamped to this value to avoid seeking past short videos.

    Returns:
        A time in seconds suitable for the ffmpeg -ss parameter, guaranteed
        to be no later than max_search.
    """
    try:
        result = subprocess.run(
            ["ffmpeg", "-i", file_path, "-vf", "blackdetect=d=0.3:pix_th=0.1",
             "-f", "null", "-"],
            capture_output=True, text=True, timeout=30
        )
        black_end = None
        for m in re.finditer(r'black_duration:([\d.]+)\s*black_start:([\d.]+)',
                             result.stderr):
            duration = float(m.group(1))
            start = float(m.group(2))
            end = start + duration
            if end > (black_end or 0):
                black_end = end
        if black_end is not None:
            t = black_end + 1.0
            return min(t, float(max_search))
    except Exception:
        pass
    return 2.0

@app.get(
    "/api/thumbnail/{resource_id}",
    summary="Generate or retrieve a thumbnail for a resource",
    description="Returns a cached PNG thumbnail for the given resource, generating it on"
    " demand if not yet cached. For textbooks/notes/PYQs/pastPapers the first PDF page is"
    " rendered via PyMuPDF at 0.3x scale. For videos ffmpeg extracts a frame at a time"
    " offset chosen by _find_video_thumb_time() to skip black intros, scaled to 320px"
    " wide. Thumbnails are cached to thumbnails/{resource_id}.png.",
    tags=["Thumbnails"],
    responses={
        200: {"description": "PNG thumbnail image", "content": {"image/png": {}}},
        404: {"description": "Resource not found, file not found, or thumbnail generation failed"},
        500: {"description": "Internal error during rendering"},
    },
)
async def resource_thumbnail(resource_id: int):
    """Fetch a thumbnail for the resource identified by `resource_id`.

    Args:
        resource_id: Primary key of the resource in the SQLite database.

    Returns:
        FileResponse serving the cached PNG thumbnail.

    Raises:
        HTTPException 404: If the resource does not exist, the source file is
            missing, or thumbnail generation fails (e.g. PyMuPDF not installed).
        HTTPException 500: On unexpected rendering errors.
    """
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT file_path, type FROM resources WHERE id = ?", (resource_id,))
    row = c.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Resource not found")
    file_path, rtype = row
    thumb_path = os.path.join(THUMBNAILS_DIR, f"{resource_id}.png")
    if os.path.exists(thumb_path):
        return FileResponse(thumb_path, media_type="image/png")
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    try:
        if rtype in ("textbook", "notes", "pyq", "pastPaper"):
            try:
                import fitz
                doc = fitz.open(file_path)
                page = doc[0]
                pix = page.get_pixmap(matrix=fitz.Matrix(0.3, 0.3))
                pix.save(thumb_path)
                doc.close()
            except ImportError:
                raise HTTPException(status_code=404, detail="Thumbnail unavailable (PyMuPDF not installed)")
        elif rtype == "videos":
            import subprocess
            thumb_time = _find_video_thumb_time(file_path)
            ss = f"{int(thumb_time // 3600):02d}:{int((thumb_time % 3600) // 60):02d}:{int(thumb_time % 60):02d}"
            result = subprocess.run(
                ["ffmpeg", "-i", file_path, "-ss", ss, "-vframes", "1", "-vf", "scale=320:-1", thumb_path, "-y"],
                capture_output=True, timeout=15
            )
            if result.returncode != 0 or not os.path.exists(thumb_path):
                raise HTTPException(status_code=404, detail="Thumbnail generation failed")
        else:
            raise HTTPException(status_code=404, detail="No thumbnail for this type")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Thumbnail error: {e}")
    return FileResponse(thumb_path, media_type="image/png")

# Static routes
@app.get("/welcome")
@app.get("/welcome.html")
async def welcome_page():
    return FileResponse("static/welcome.html")

@app.get("/dashboard")
@app.get("/index.html")
async def get_dashboard(request: Request):
    if not request.cookies.get("lumina_session"):
        return RedirectResponse(url="/welcome")
    return FileResponse("static/index.html")

# WhoAmI endpoint – tells the client its role
@app.get("/whoami")
async def whoami(user: dict = Depends(_extract_user)):
    return {"username": user["username"], "role": user["role"]}

# Admin audit log (last N entries, default 20)
@app.get("/admin/log")
async def admin_log(limit: int = 20, admin_user: str = Depends(verify_admin)):
    async with _admin_log_lock:
        try:
            with open("data/admin_actions.log", "r") as f:
                lines = f.readlines()[-limit:]
            return {"log": [line.strip() for line in lines]}
        except FileNotFoundError:
            return {"log": []}

class LogRetentionUpdate(BaseModel):
    policy: str # e.g. "24h", "7d", "30d", "3m", "6m", "never", "none"

@app.get("/api/admin/settings")
async def get_admin_settings(admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT value FROM settings WHERE key = 'log_retention'")
    row = c.fetchone()
    conn.close()
    return {"log_retention": row[0] if row else "30d"}

@app.post("/api/admin/settings")
async def set_admin_settings(data: LogRetentionUpdate, admin_user: str = Depends(verify_admin)):
    if data.policy not in ("24h", "7d", "30d", "3m", "6m", "never", "none"):
        raise HTTPException(status_code=400, detail="Invalid log retention policy.")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('log_retention', ?)", (data.policy,))
    conn.commit()
    conn.close()
    await log_admin_action(admin_user, f"changed log retention policy to {data.policy}")
    return {"status": "success"}

@app.get("/api/admin/admins")
async def list_admins(admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT username, name, department, reset_required FROM users WHERE role = 'admin' ORDER BY name ASC")
        rows = c.fetchall()
    except sqlite3.OperationalError:
        c.execute("SELECT username, name, department, 0 as reset_required FROM users WHERE role != 'teacher' OR role IS NULL ORDER BY name ASC")
        rows = c.fetchall()
    conn.close()
    return [{"username": r[0], "name": r[1] or r[0], "department": r[2] or "System", "reset_required": r[3] or 0} for r in rows]

@app.post("/api/admin/create")
async def create_admin(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT username FROM users WHERE username = ?", (data.username,))
        if c.fetchone():
            raise HTTPException(status_code=400, detail="Username already exists.")
        display_name = data.name or data.username
        dept = data.department or "System"
        admin_id = f"LUMINA_01-T{uuid.uuid4().hex}"
        hashed_pwd = hash_password(data.password)
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'admin')",
                  (data.username, hashed_pwd, display_name, dept, admin_id))
        conn.commit()
        await log_admin_action(admin_user, f"created admin account '{data.username}'")
        return {"status": "success", "username": data.username, "name": display_name, "scholar_id": admin_id}
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] create_admin: {e}")
        raise HTTPException(status_code=400, detail="Failed to create admin account")
    finally:
        conn.close()

@app.post("/api/admin/create-teacher")
async def create_teacher(data: TeacherCreate, admin_user: str = Depends(verify_admin)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT username FROM users WHERE username = ?", (data.username,))
        if c.fetchone():
            raise HTTPException(status_code=400, detail="Username already exists.")
        display_name = data.name or data.username
        dept = data.department or "General"
        teacher_id = f"LUMINA_01-T{uuid.uuid4().hex}"
        hashed_pwd = hash_password(data.password)
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id, role) VALUES (?, ?, ?, ?, ?, 'teacher')",
                  (data.username, hashed_pwd, display_name, dept, teacher_id))
        conn.commit()
        await log_admin_action(admin_user, f"created teacher account '{data.username}'")
        return {"status": "success", "username": data.username, "name": display_name, "scholar_id": teacher_id}
    except HTTPException:
        raise
    except Exception as e:
        print(f"[ERROR] create_teacher: {e}")
        raise HTTPException(status_code=400, detail="Failed to create teacher account")
    finally:
        conn.close()

@app.get("/api/admin/logs/download")
async def download_admin_logs(duration: str = "all", admin_user: str = Depends(verify_admin)):
    if not os.path.exists("data/admin_actions.log"):
        return Response(content="No logs found.", media_type="text/plain")

    ALLOWED_DURATIONS = {"24h", "7d", "30d", "3m", "6m", "all"}
    if duration not in ALLOWED_DURATIONS:
        duration = "all"

    cutoff = None
    now = datetime.now().timestamp()
    if duration == "24h":
        cutoff = now - 24 * 3600
    elif duration == "7d":
        cutoff = now - 7 * 24 * 3600
    elif duration == "30d":
        cutoff = now - 30 * 24 * 3600
    elif duration == "3m":
        cutoff = now - 90 * 24 * 3600
    elif duration == "6m":
        cutoff = now - 180 * 24 * 3600

    filtered_lines = []
    with open("data/admin_actions.log", "r") as f:
        for line in f:
            if cutoff is None:
                filtered_lines.append(line)
            else:
                parts = line.split(" - ", 1)
                try:
                    log_time = datetime.fromisoformat(parts[0])
                    if log_time.timestamp() >= cutoff:
                        filtered_lines.append(line)
                except Exception:
                    filtered_lines.append(line)

    content = "".join(filtered_lines)
    return Response(
        content=content,
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=admin_logs_{duration}.txt"}
    )

@app.get("/student/profile")
async def get_student_profile(student_id: str = Depends(verify_student)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT name, grade, id FROM scholars WHERE id = ?", (student_id,))
    row = c.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=404, detail="Student not found")
    return {"name": row[0], "grade": row[1] or "", "scholar_id": row[2]}

# --- Teacher: Student Monitor ---

@app.get("/teacher/students")
async def teacher_list_students(teacher_user: str = Depends(verify_teacher), grade: Optional[str] = Query(default=None)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        # Get distinct grades that have students
        grade_filter = "WHERE grade = ?" if grade else ""
        params = (grade,) if grade else ()
        c.execute(f"""
            SELECT
                s.id,
                s.name,
                s.username,
                s.grade,
                COALESCE(t.today_secs, 0) AS today_secs,
                COALESCE(w.week_secs, 0) AS week_secs,
                COALESCE(sv.saved, 0) AS saved,
                COALESCE(sd.downloaded, 0) AS downloaded,
                la.last_active
            FROM scholars s
            LEFT JOIN (SELECT scholar_id, SUM(duration_seconds) AS today_secs FROM study_sessions WHERE date(start_time) = date('now') GROUP BY scholar_id) t ON t.scholar_id = s.id
            LEFT JOIN (SELECT scholar_id, SUM(duration_seconds) AS week_secs FROM study_sessions WHERE start_time >= datetime('now', '-7 days') GROUP BY scholar_id) w ON w.scholar_id = s.id
            LEFT JOIN (SELECT scholar_id, COUNT(*) AS saved FROM scholar_downloads GROUP BY scholar_id) sv ON sv.scholar_id = s.id
            LEFT JOIN (SELECT scholar_id, COUNT(*) AS downloaded FROM activity_logs WHERE action = 'download' GROUP BY scholar_id) sd ON sd.scholar_id = s.id
            LEFT JOIN (SELECT scholar_id, MAX(timestamp) AS last_active FROM activity_logs GROUP BY scholar_id) la ON la.scholar_id = s.id
            {grade_filter}
            ORDER BY la.last_active DESC NULLS LAST, s.name ASC
        """, params)
        students = []
        for row in c.fetchall():
            sid, name, username, sgrade, today_secs, week_secs, saved, downloaded, last_active = row
            # Calculate streak for each student
            c.execute("SELECT DISTINCT date(timestamp) as d FROM activity_logs WHERE scholar_id = ? ORDER BY d DESC", (sid,))
            active_days = [r[0] for r in c.fetchall()]
            streak = 0
            today_d = datetime.now().date()
            for i, d in enumerate(active_days):
                expected = today_d - timedelta(days=i)
                try:
                    if datetime.strptime(d, "%Y-%m-%d").date() == expected:
                        streak += 1
                    else:
                        break
                except ValueError:
                    break
            students.append({
                "id": sid,
                "name": name or username or "",
                "username": username or "",
                "grade": sgrade or "",
                "study_minutes_today": today_secs // 60,
                "study_minutes_this_week": week_secs // 60,
                "streak_days": streak,
                "resources_saved": saved,
                "resources_downloaded": downloaded,
                "last_active": last_active or "",
            })
    except sqlite3.OperationalError as e:
        conn.close()
        raise HTTPException(status_code=500, detail=f"Database error: {e}")
    conn.close()
    # TEMP DEMO: return fake students when no real ones exist
    if not students:
        demo = []
        now = datetime.now()
        demo_students = [
            ("LUMINA_DEMO_01", "Ananya Sharma", "ananya", "Grade 10", 35, 210, 5, 18, 12),
            ("LUMINA_DEMO_02", "Rohit Kumar", "rohit", "Grade 10", 12, 95, 2, 8, 6),
            ("LUMINA_DEMO_03", "Priya Patel", "priya", "Grade 9", 48, 310, 7, 22, 15),
            ("LUMINA_DEMO_04", "Arjun Singh", "arjun", "Grade 11", 20, 150, 3, 14, 9),
            ("LUMINA_DEMO_05", "Sneha Reddy", "sneha", "Grade 9", 55, 380, 10, 25, 18),
            ("LUMINA_DEMO_06", "Vikram Joshi", "vikram", "Grade 12", 5, 45, 1, 6, 3),
            ("LUMINA_DEMO_07", "Kavita Nair", "kavita", "Grade 10", 28, 175, 4, 15, 11),
            ("LUMINA_DEMO_08", "Divya Menon", "divya", "Grade 11", 40, 260, 6, 20, 14),
            ("LUMINA_DEMO_09", "Rahul Verma", "rahul", "Grade 9", 18, 130, 3, 10, 7),
            ("LUMINA_DEMO_10", "Meera Iyer", "meera", "Grade 12", 30, 200, 5, 16, 10),
        ]
        for sid, name, uname, grd, td, wk, st, sv, dl in demo_students:
            demo.append({
                "id": sid, "name": name, "username": uname, "grade": grd,
                "study_minutes_today": td, "study_minutes_this_week": wk,
                "streak_days": st, "resources_saved": sv, "resources_downloaded": dl,
                "last_active": (now - timedelta(minutes=td * 3)).isoformat(),
            })
        if grade:
            demo = [s for s in demo if s["grade"] == grade]
        return {"students": demo}
    return {"students": students}


@app.get("/teacher/student/{scholar_id}/analytics")
async def teacher_student_analytics(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT name FROM scholars WHERE id = ?", (scholar_id,))
    scholar = c.fetchone()
    if not scholar:
        conn.close()
        # TEMP DEMO: return fake analytics when student not found
        if scholar_id.startswith("LUMINA_DEMO"):
            demo_analytics = {
                "LUMINA_DEMO_01": (35, 210, 900, 5, 18, [("Mathematics", 80), ("Science", 60), ("English", 40), ("History", 30)]),
                "LUMINA_DEMO_02": (12, 95, 400, 2, 8, [("Mathematics", 30), ("Science", 25), ("English", 20), ("Geography", 20)]),
                "LUMINA_DEMO_03": (48, 310, 1200, 7, 22, [("Science", 100), ("Mathematics", 90), ("English", 60), ("Hindi", 60)]),
                "LUMINA_DEMO_04": (20, 150, 650, 3, 14, [("Physics", 50), ("Chemistry", 40), ("Mathematics", 35), ("Biology", 25)]),
                "LUMINA_DEMO_05": (55, 380, 1500, 10, 25, [("Mathematics", 120), ("Science", 100), ("English", 80), ("History", 50), ("Geography", 30)]),
                "LUMINA_DEMO_06": (5, 45, 200, 1, 6, [("Physics", 15), ("Chemistry", 15), ("Mathematics", 15)]),
                "LUMINA_DEMO_07": (28, 175, 750, 4, 15, [("Mathematics", 60), ("Science", 45), ("English", 40), ("History", 30)]),
                "LUMINA_DEMO_08": (40, 260, 1100, 6, 20, [("Chemistry", 70), ("Physics", 65), ("Mathematics", 60), ("Biology", 45), ("English", 20)]),
                "LUMINA_DEMO_09": (18, 130, 550, 3, 10, [("Science", 45), ("Mathematics", 40), ("English", 25), ("Geography", 20)]),
                "LUMINA_DEMO_10": (30, 200, 850, 5, 16, [("Physics", 55), ("Mathematics", 50), ("Chemistry", 45), ("English", 30), ("Biology", 20)]),
            }
            if scholar_id in demo_analytics:
                td, wk, mo, st, sv, subs = demo_analytics[scholar_id]
                return {
                    "study_minutes_today": td, "study_minutes_this_week": wk,
                    "study_minutes_this_month": mo, "streak_days": st,
                    "resources_saved": sv,
                    "subjects": [{"name": n, "minutes": m} for n, m in subs],
                }
        raise HTTPException(status_code=404, detail="Student not found")
    c.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM study_sessions WHERE scholar_id = ? AND date(start_time) = date('now')", (scholar_id,))
    today_secs = c.fetchone()[0]
    c.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM study_sessions WHERE scholar_id = ? AND start_time >= datetime('now', '-7 days')", (scholar_id,))
    week_secs = c.fetchone()[0]
    c.execute("SELECT COALESCE(SUM(duration_seconds), 0) FROM study_sessions WHERE scholar_id = ? AND strftime('%Y-%m', start_time) = strftime('%Y-%m', 'now')", (scholar_id,))
    month_secs = c.fetchone()[0]
    c.execute("SELECT metadata, COUNT(*) as cnt FROM activity_logs WHERE scholar_id = ? AND action = 'view' AND metadata != '' GROUP BY metadata ORDER BY cnt DESC", (scholar_id,))
    subject_rows = c.fetchall()
    c.execute("SELECT DISTINCT date(timestamp) as d FROM activity_logs WHERE scholar_id = ? ORDER BY d DESC", (scholar_id,))
    active_days = [r[0] for r in c.fetchall()]
    streak = 0
    today_d = datetime.now().date()
    for i, d in enumerate(active_days):
        expected = today_d - timedelta(days=i)
        try:
            if datetime.strptime(d, "%Y-%m-%d").date() == expected:
                streak += 1
            else:
                break
        except ValueError:
            break
    c.execute("SELECT COUNT(*) FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
    saved = c.fetchone()[0]
    conn.close()
    return {
        "study_minutes_today": today_secs // 60,
        "study_minutes_this_week": week_secs // 60,
        "study_minutes_this_month": month_secs // 60,
        "streak_days": streak,
        "resources_saved": saved,
        "subjects": [{"name": r[0], "minutes": r[1] * 5} for r in subject_rows],
    }


@app.get("/teacher/student/{scholar_id}/activity")
async def teacher_student_activity(scholar_id: str, teacher_user: str = Depends(verify_teacher), limit: int = Query(default=50, ge=1, le=500), offset: int = Query(default=0, ge=0)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM activity_logs WHERE scholar_id = ?", (scholar_id,))
    total = c.fetchone()[0]
    c.execute("SELECT rowid AS id, action, resource_id, metadata, timestamp FROM activity_logs WHERE scholar_id = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?",
              (scholar_id, limit, offset))
    rows = c.fetchall()
    conn.close()
    # TEMP DEMO: return fake activity when no real data exists for demo IDs
    if total == 0 and rows == [] and scholar_id.startswith("LUMINA_DEMO"):
        now = datetime.now()
        demo_actions = [
            ("view", "Ch1", "Chapter 1: Real Numbers"),
            ("view", "Ch2", "Chapter 2: Polynomials"),
            ("download", "Ch1", "Chapter 1: Real Numbers"),
            ("search", "", "algebra equations"),
            ("view", "Ch3", "Chapter 3: Linear Equations"),
            ("save", "Ch2", "Chapter 2: Polynomials"),
            ("view", "Ch4", "Chapter 4: Quadratic Equations"),
            ("search", "", "trigonometry basics"),
            ("view", "Ch5", "Chapter 5: Arithmetic Progressions"),
            ("download", "Ch3", "Chapter 3: Linear Equations"),
            ("view", "Ch6", "Chapter 6: Triangles"),
            ("search", "", "probability problems"),
            ("view", "Ch7", "Chapter 7: Coordinate Geometry"),
            ("save", "Ch5", "Chapter 5: Arithmetic Progressions"),
            ("view", "Ch8", "Chapter 8: Introduction to Trigonometry"),
        ]
        activity = []
        for i, (action, rid, meta) in enumerate(demo_actions):
            ts = now - timedelta(minutes=i * 15, seconds=i * 7)
            activity.append({
                "id": i + 1, "action": action, "resource_id": rid,
                "metadata": meta, "timestamp": ts.isoformat(),
            })
        return {"activity": activity, "total": len(activity), "limit": limit, "offset": offset}
    return {
        "activity": [{"id": r[0], "action": r[1], "resource_id": r[2], "metadata": r[3], "timestamp": r[4]} for r in rows],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


# Mount file uploads directory (no auth — files are accessed by download links)
app.mount("/files", StaticFiles(directory="uploads"), name="files")

# Serve static files with auth — HTML pages require teacher/admin session
@app.get("/static/{path:path}")
async def serve_static(path: str, request: Request):
    # Redirect .html URLs to clean URLs (e.g. /static/manage-content.html → /static/manage-content)
    if path.endswith(".html"):
        clean = path[:-5]
        return RedirectResponse(url=f"/static/{clean}", status_code=301)

    # Try exact path first, then append .html for clean URLs
    def _resolve(p: str) -> str | None:
        fp = os.path.join("static", p)
        if os.path.isfile(fp):
            return fp
        if os.path.isfile(fp + ".html"):
            return fp + ".html"
        return None

    # Public assets — always accessible
    if path.startswith("css/") or path.startswith("js/") or path == "welcome.html" or path == "welcome":
        file_path = _resolve(path)
        if file_path:
            return FileResponse(file_path)
        raise HTTPException(status_code=404, detail="File not found")

    # Protected HTML pages — require valid teacher/admin session
    user = _extract_user(request)
    if user["role"] not in ("teacher", "admin"):
        raise HTTPException(status_code=403, detail="Teacher access required")
    file_path = _resolve(path)
    if file_path:
        return FileResponse(file_path)
    raise HTTPException(status_code=404, detail="File not found")

from zim_handler import router as zim_router
app.include_router(zim_router, prefix="/zim")
