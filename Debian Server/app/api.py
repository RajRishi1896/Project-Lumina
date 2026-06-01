# Fixed api.py for Lumina EduMesh Hub
from fastapi import FastAPI, UploadFile, File, Depends, HTTPException, status, Request, Response, Form, Query
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
import os
import subprocess
from .zim_auto_cleaner import start_zim_auto_cleaner
import sqlite3
import shutil
import logging
import uuid
import zipfile
import threading

try:
    _disk = shutil.disk_usage("/")
    # Set ZIM_UPLOAD_MAX_SIZE to less than the system size (total capacity minus 1 GiB buffer)
    ZIM_UPLOAD_MAX_SIZE = max(0, _disk.total - 1024 * 1024 * 1024)
except Exception:
    ZIM_UPLOAD_MAX_SIZE = 5000 * 1024 * 1024  # Fallback to 5 GiB if disk check fails


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
_admin_log_lock = threading.Lock()

def log_admin_action(username: str, action: str):
    try:
        with _admin_log_lock:
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
        with _admin_log_lock:
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
                with _admin_log_lock:
                    with open("data/admin_actions.log", "w") as f:
                        f.writelines(kept_lines)
    except Exception as e:
        logging.error(f"Error pruning logs: {e}")

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
app.add_middleware(CORSMiddleware,     allow_origins=["http://localhost:8000", "http://127.0.0.1:8000", "http://lumina.hub:8000", "http://10.42.0.1:8000", "http://10.42.0.1"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "Cache-Control"],)

# --- Anti‑Spam Rate Limiter ---
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.ip_records = {}
        self._lock = threading.Lock()
        import asyncio
        asyncio.create_task(self.cleanup_stale())

    async def cleanup_stale(self):
        while True:
            await asyncio.sleep(300)
            with self._lock:
                now = time.time()
                self.ip_records = {
                    ip: [t for t in ts if now - t < 60]
                    for ip, ts in self.ip_records.items()
                }

    async def dispatch(self, request: Request, call_next):
        client_ip = request.client.host if request.client else request.headers.get("X-Forwarded-For", "unknown")
        path = request.url.path
        with self._lock:
            now = time.time()
            timestamps = self.ip_records.get(client_ip, [])
            timestamps = [t for t in timestamps if now - t < 60]

            strict_paths = ["/token", "/teacher", "/register", "/logout", "/student/token"]
            if any(path.startswith(p) for p in strict_paths):
                if len(timestamps) >= 15:
                    logging.warning(f"BLOCKED: Strict rate limit exceeded by IP {client_ip} on {path}")
                    return Response(content="Rate limit exceeded. Please wait 60 seconds.", status_code=429)

            if len(timestamps) >= 100:
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
    response.headers["Cache-Control"] = "no-store"
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
    c.execute('CREATE TABLE IF NOT EXISTS activity_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, action TEXT, resource_id TEXT, metadata TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    c.execute('CREATE TABLE IF NOT EXISTS study_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, scholar_id TEXT, start_time DATETIME, end_time DATETIME, duration_seconds INTEGER)')
    c.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)')
    try:
        c.execute('ALTER TABLE sessions ADD COLUMN role TEXT')
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
        c.execute('ALTER TABLE resources ADD COLUMN subject TEXT')
    except sqlite3.OperationalError:
        pass # Column already exists
        
    try:
        default_pwd = hash_password("lumina2026")
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id) VALUES (?, ?, ?, ?, ?)", ("admin", default_pwd, "Administrator", "System", "LUMINA_01-ADMIN"))
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
    name: str = Field(..., min_length=1, max_length=100)
    password: Optional[str] = Field(default="lumina2026", min_length=4, max_length=128)

class StudentLoginRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=100)
    password: str = Field(..., min_length=1, max_length=128)

class StudentChangePasswordRequest(BaseModel):
    scholar_id: str = Field(..., max_length=100)
    old_password: str = Field(..., max_length=128)
    new_password: str = Field(..., min_length=4, max_length=128)

class SubjectDeleteRequest(BaseModel):
    name: str
    transfer_to: Optional[str] = None

class SyncActivity(BaseModel):
    action: str
    resource_id: str

class ChangePasswordRequest(BaseModel):
    old_password: str
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
    return RedirectResponse(url="/welcome.html")

# --- Auth Functions ---

def _extract_user(request: Request) -> dict:
    auth = request.headers.get("Authorization")
    cookie = request.cookies.get("lumina_session")
    if not cookie and not (auth and auth.startswith("Bearer ")):
        raise HTTPException(status_code=401, detail="Unauthorized: Session required.")
    token = cookie or (auth.removeprefix("Bearer ") if auth else "")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    cur = conn.cursor()
    cur.execute("SELECT s.username, s.role FROM sessions s JOIN users u ON s.username = u.username WHERE s.token = ? AND s.created_at > datetime('now', '-24 hours')", (token,))
    row = cur.fetchone()
    if row:
        conn.close()
        return {"username": row[0], "role": row[1]}
    cur.execute("SELECT s.username, 'student' as role FROM sessions s JOIN scholars sc ON s.username = sc.id WHERE s.token = ? AND s.created_at > datetime('now', '-24 hours')", (token,))
    row = cur.fetchone()
    conn.close()
    if row:
        return {"username": row[0], "role": "student"}
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
    cur.execute("SELECT username FROM sessions WHERE token = ? AND role = 'student' AND created_at > datetime('now', '-24 hours')", (token,))
    row = cur.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=401, detail="Invalid or expired student session")
    return row[0]

# --- Endpoints ---

@app.get("/ping")
async def ping_server():
    return {"status": "pong"}

@app.get("/files")
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
async def system_stats():
    return {"status": "healthy"}

@app.post("/system/sync-time")
async def sync_time(data: TimeSync, admin_user: str = Depends(verify_admin)):
    try:
        if not data.current_time or len(data.current_time) >= 64:
            return {"status": "failed"}
        if not re.match(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$', data.current_time):
            return {"status": "failed"}
        result = subprocess.run(["date", "-s", data.current_time], capture_output=True, text=True)
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
    c.execute("SELECT id, action, resource_id, metadata, timestamp FROM activity_logs WHERE scholar_id = ? ORDER BY timestamp DESC LIMIT ? OFFSET ?",
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
async def update_student_profile(data: ProfileUpdate, student_id: str = Depends(verify_student)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        if data.name:
            c.execute("UPDATE scholars SET name = ? WHERE id = ?", (data.name, student_id))
        if data.grade:
            try:
                c.execute("ALTER TABLE scholars ADD COLUMN grade TEXT")
            except sqlite3.OperationalError:
                pass
            c.execute("UPDATE scholars SET grade = ? WHERE id = ?", (data.grade, student_id))
        conn.commit()
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
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
async def register_scholar(scholar: ScholarReg):
    unique_suffix = uuid.uuid4().hex
    full_id = f"LUMINA_01-{unique_suffix}"
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        pwd = scholar.password or "lumina2026"
        if scholar.password:
            valid, msg = validate_password_strength(pwd)
            if not valid:
                raise HTTPException(status_code=400, detail=msg)
        hashed = hash_password(pwd)
        c.execute("INSERT INTO scholars (id, name, hashed_password, reset_required) VALUES (?, ?, ?, 0)", (full_id, scholar.name, hashed))
        token = f"LUMINA_HUB-{uuid.uuid4().hex}"
        c.execute("INSERT INTO sessions (token, username, role) VALUES (?, ?, 'student')", (token, full_id))
        conn.commit()
        response = JSONResponse({"id": full_id, "token": token})
        response.set_cookie(key="lumina_session", value=token, httponly=True, samesite="strict", secure=True, max_age=86400)
        return response
    except Exception as e:
        print(f"[ERROR] register_scholar: {e}")
        raise HTTPException(status_code=400, detail="Registration failed")
    finally:
        conn.close()

# Student Token / Login
@app.post("/student/token")
async def student_login(data: StudentLoginRequest):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT id, hashed_password, reset_required FROM scholars WHERE name = ?", (data.username,))
    row = c.fetchone()
    conn.close()
    
    if not row:
        raise HTTPException(status_code=401, detail="Student account not found.")
    
    scholar_id, hashed_pwd, reset_req = row

    pwd_to_check = hashed_pwd
    if not pwd_to_check:
        raise HTTPException(status_code=401, detail="Password not set. Contact teacher to set your password.")

    if not verify_password(data.password, pwd_to_check):
        raise HTTPException(status_code=401, detail="Invalid student credentials.")
    
    token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO sessions (token, username, role) VALUES (?, ?, 'student')", (token, scholar_id))
    c.execute("DELETE FROM sessions WHERE created_at < datetime('now', '-24 hours')")
    conn.commit()
    conn.close()
    
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT name FROM scholars WHERE id = ?", (scholar_id,))
    srow = c.fetchone()
    conn.close()
    
    response = JSONResponse({"status": "ok", "scholar_id": scholar_id, "token": token, "name": srow[0] if srow else data.username, "reset_required": bool(reset_req)})
    response.set_cookie(key="lumina_session", value=token, httponly=True, samesite="strict", max_age=86400, secure=True)
    return response

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
async def get_subjects():
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT name, symbol, class_name FROM subjects ORDER BY class_name ASC, name ASC")
        rows = c.fetchall()
        return [{"name": r[0], "symbol": r[1], "class_name": r[2] or "All Classes"} for r in rows]
    except sqlite3.OperationalError:
        c.execute("SELECT name, symbol FROM subjects ORDER BY name ASC")
        rows = c.fetchall()
        return [{"name": r[0], "symbol": r[1], "class_name": "All Classes"} for r in rows]
    finally:
        conn.close()

# Teacher Profile Management API
@app.post("/teacher/subjects")
async def create_subject(subject: SubjectCreate, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        class_val = subject.class_name or "All Classes"
        c.execute("INSERT OR REPLACE INTO subjects (name, symbol, class_name) VALUES (?, ?, ?)", (subject.name, subject.symbol, class_val))
        conn.commit()
        return {"status": "success", "name": subject.name, "symbol": subject.symbol, "class_name": class_val}
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
async def create_teacher_profile(teacher: TeacherCreate, teacher_user: str = Depends(verify_teacher)):
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
async def get_limits():
    return {"zim_upload_max_size": ZIM_UPLOAD_MAX_SIZE}

@app.get("/stats")
async def get_stats():
    total, used, free = shutil.disk_usage("/")
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
        c.execute("SELECT id, title, file_path, type, subject FROM resources")
    except sqlite3.OperationalError:
        c.execute("SELECT id, title, file_path, type, 'General' as subject FROM resources")
    rows = c.fetchall()
    conn.close()
    return [{"id": r[0], "title": r[1], "url": f"/files/{os.path.basename(r[2])}", "type": r[3], "subject": r[4] or "General"} for r in rows]

@app.post("/teacher/upload")
async def upload_resource(title: str, resource_type: str, subject: str = "General", file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher)):
    total, used, free = shutil.disk_usage("/")
    free_gb = free // (2**30)
    if free_gb < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename or 'unnamed_file')
    file_path = os.path.join(UPLOAD_DIR, safe_filename)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
    contents = await file.read()
    if len(contents) > 100 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="File too large")
    with open(file_path, "wb") as buffer:
        buffer.write(contents)
    await file.close()
    try:
        c.execute("INSERT INTO resources (title, file_path, type, subject) VALUES (?, ?, ?, ?)", (title, file_path, resource_type, subject))
    except sqlite3.OperationalError:
        c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)", (title, file_path, resource_type))
    conn.commit()
    conn.close()
    return {"status": "success"}
@app.post("/teacher/upload-zim")
async def upload_zim(
    file: UploadFile = File(...),
    teacher_user: str = Depends(verify_teacher)
):
    # Storage space check (minimum 2 GB free)
    total, used, free = shutil.disk_usage("/")
    free_gb = free // (2**30)
    if free_gb < 2:
        raise HTTPException(status_code=507, detail="Insufficient storage space for ZIM upload.")
    contents = await file.read()
    if len(contents) > ZIM_UPLOAD_MAX_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"ZIM upload exceeds maximum size limit of {ZIM_UPLOAD_MAX_SIZE // (1024 * 1024)} MiB."
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
async def login(response: Response, username: str = Form(...), password: str = Form(...)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("SELECT hashed_password, name, department, scholar_id, reset_required, role FROM users WHERE username = ?", (username,))
        row = c.fetchone()
        reset_req = row[4] if row else 0
        if username == "admin":
            reset_req = 0
    except sqlite3.OperationalError:
        c.execute("SELECT hashed_password, username as name, 'General' as department, 'LUMINA_01-TEACHER' as scholar_id FROM users WHERE username = ?", (username,))
        row = c.fetchone()
        reset_req = 0
    conn.close()
    if not row or not verify_password(password, row[0]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")
    
    user_role = row[5] if (row and len(row) > 5) else ("admin" if username == "admin" else "teacher")
    session_token = f"LUMINA_HUB-{uuid.uuid4().hex}"
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("DELETE FROM sessions WHERE created_at < datetime('now', '-24 hours')")
    c.execute("INSERT INTO sessions (token, username, role) VALUES (?, ?, ?)", (session_token, username, user_role))
    conn.commit()
    conn.close()
    response.set_cookie(key="lumina_session", value=session_token, httponly=True, max_age=86400, samesite="strict", secure=True)
    return {
        "access_token": session_token,
        "token_type": "bearer",
        "username": username,
        "name": row[1] or username,
        "department": row[2] or "General",
        "scholar_id": row[3] or f"LUMINA_01-T_{username.upper()}",
        "role": user_role,
        "reset_required": reset_req or 0
    }

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
    return RedirectResponse(url="/welcome.html")

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
    log_admin_action(admin_user, "disabled the default admin account")
    return {"status": "success"}

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

@app.post("/teacher/reset-password/{username}")
async def force_reset_teacher_password(username: str, admin_user: str = Depends(verify_admin)):
    if username == "admin" and admin_user != "admin":
        raise HTTPException(status_code=400, detail="Only the main admin can reset the default admin account.")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        hashed = hash_password("lumina2026")
        c.execute("UPDATE users SET hashed_password = ?, reset_required = 1 WHERE username = ?", (hashed, username))
        conn.commit()
        log_admin_action(admin_user, f"reset password for teacher {username}")
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
        # Check if subject exists
        c.execute("SELECT name FROM subjects WHERE name = ?", (data.name,))
        if not c.fetchone():
            raise HTTPException(status_code=404, detail="Subject not found.")
            
        if data.transfer_to:
            c.execute("UPDATE resources SET subject = ? WHERE subject = ?", (data.transfer_to, data.name))
        else:
            c.execute("SELECT file_path FROM resources WHERE subject = ?", (data.name,))
            files = [r[0] for r in c.fetchall()]
            for fp in files:
                if os.path.exists(fp):
                    try:
                        os.remove(fp)
                    except Exception as e:
                        logging.warning(f"Could not remove physical file {fp}: {e}")
            c.execute("DELETE FROM resources WHERE subject = ?", (data.name,))
            
        c.execute("DELETE FROM subjects WHERE name = ?", (data.name,))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"[ERROR] delete_subject: {e}")
        raise HTTPException(status_code=400, detail="Failed to delete subject")
    finally:
        conn.close()

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

# Static routes
@app.get("/welcome.html")
async def welcome_page():
    return FileResponse("static/welcome.html")

@app.get("/dashboard")
@app.get("/index.html")
async def get_dashboard(request: Request):
    if not request.cookies.get("lumina_session"):
        return RedirectResponse(url="/welcome.html")
    return FileResponse("static/index.html")

# WhoAmI endpoint – tells the client its role
@app.get("/whoami")
async def whoami(user: dict = Depends(_extract_user)):
    return {"username": user["username"], "role": user["role"]}

# Admin audit log (last N entries, default 20)
@app.get("/admin/log")
async def admin_log(limit: int = 20, admin_user: str = Depends(verify_admin)):
    with _admin_log_lock:
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
    log_admin_action(admin_user, f"changed log retention policy to {data.policy}")
    return {"status": "success"}

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

# Mount static directories
app.mount("/files", StaticFiles(directory="uploads"), name="files")
app.mount("/static", StaticFiles(directory="static"), name="public_static")

from zim_handler import router as zim_router
app.include_router(zim_router, prefix="/zim")
