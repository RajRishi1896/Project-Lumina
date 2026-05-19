# Fixed api.py for Lumina EduMesh Hub
from fastapi import FastAPI, UploadFile, File, Depends, HTTPException, status, Request, Response, Form
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, RedirectResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
import os
import sqlite3
import shutil
import logging
import uuid
import re
import time
from pydantic import BaseModel
from typing import List, Optional
from passlib.context import CryptContext
from datetime import datetime
from logging.handlers import RotatingFileHandler

# --- Logging ---
os.makedirs("data", exist_ok=True)
log_handler = RotatingFileHandler('data/hub.log', maxBytes=5*1024*1024, backupCount=3)
logging.basicConfig(handlers=[log_handler], level=logging.INFO, format='%(asctime)s - %(message)s')

app = FastAPI(title="Lumina EduMesh Hub")

# Security
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# --- Anti‑Spam Rate Limiter ---
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.ip_records = {}

    async def dispatch(self, request: Request, call_next):
        client_ip = request.client.host
        path = request.url.path
        now = time.time()
        records = self.ip_records.get(client_ip, [])
        records = [t for t in records if now - t < 60]
        
        # Tier 1: Strict limits for Auth, Admin, Uploads, Registration (15 req/min)
        strict_paths = ["/token", "/teacher", "/register", "/logout"]
        if any(path.startswith(p) for p in strict_paths):
            strict_count = len([t for t in records if t > now - 60])
            if strict_count >= 15:
                logging.warning(f"BLOCKED: Strict rate limit exceeded by IP {client_ip} on {path}")
                return Response(content="Rate limit exceeded. Please wait 60 seconds.", status_code=429)
        
        # Tier 2: General flood protection for catalog/files/stats (100 req/min)
        if len(records) >= 100:
            logging.warning(f"BLOCKED: General flood limit exceeded by IP {client_ip}")
            return Response(content="Too many requests. Please slow down.", status_code=429)
            
        records.append(now)
        self.ip_records[client_ip] = records
        return await call_next(request)

app.add_middleware(RateLimitMiddleware)

# Paths
UPLOAD_DIR = "uploads"
DB_PATH = "data/hub.db"
os.makedirs(UPLOAD_DIR, exist_ok=True)

# Database Setup
def init_db():
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    conn.execute('PRAGMA journal_mode=WAL')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS scholars (id TEXT PRIMARY KEY, name TEXT)')
    c.execute('CREATE TABLE IF NOT EXISTS resources (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, file_path TEXT, type TEXT)')
    c.execute('CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, hashed_password TEXT)')
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
    c.execute('CREATE TABLE IF NOT EXISTS activity_logs (scholar_id TEXT, action TEXT, resource_id TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    
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
        default_pwd = pwd_context.hash("lumina2026")
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
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    except sqlite3.OperationalError:
        pass
    conn.commit()
    conn.close()

init_db()

# Models
class TimeSync(BaseModel):
    current_time: str

class ScholarReg(BaseModel):
    name: str
    password: Optional[str] = "lumina2026"

class StudentLoginRequest(BaseModel):
    username: str
    password: str

class StudentChangePasswordRequest(BaseModel):
    scholar_id: str
    new_password: str

class SubjectDeleteRequest(BaseModel):
    name: str
    transfer_to: Optional[str] = None

class SyncActivity(BaseModel):
    scholar_id: str
    action: str
    resource_id: str

class ChangePasswordRequest(BaseModel):
    username: str
    old_password: str
    new_password: str

class SubjectCreate(BaseModel):
    name: str
    symbol: str
    class_name: Optional[str] = "All Classes"

class TeacherCreate(BaseModel):
    username: str
    password: str
    name: Optional[str] = None
    department: Optional[str] = "General"

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

# --- Endpoints ---

@app.get("/ping")
async def ping_server():
    return {"status": "pong"}

@app.get("/files")
async def list_files():
    if not os.path.exists(UPLOAD_DIR):
        return []
    files = []
    for f in os.listdir(UPLOAD_DIR):
        fp = os.path.join(UPLOAD_DIR, f)
        if os.path.isfile(fp):
            files.append({"name": f, "size": os.path.getsize(fp)})
    return files

@app.get("/system/stats")
@app.post("/system/sync-time")
async def sync_time(data: TimeSync):
    try:
        os.system(f"date -s '{data.current_time}'")
        logging.info(f"Time Synced: {data.current_time}")
        return {"status": "ok"}
    except:
        return {"status": "failed"}

# Captive portal helper
@app.get("/generate_204")
async def generate_204():
    """Tricks Android into thinking it has internet so it doesn't switch to cellular."""
    return Response(status_code=204)

# Sync activity
@app.post("/sync/activity")
async def sync_activity(data: SyncActivity):
    auto_register_if_new(data.scholar_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO activity_logs (scholar_id, action, resource_id) VALUES (?, ?, ?)", (data.scholar_id, data.action, data.resource_id))
    conn.commit()
    conn.close()
    return {"status": "synced"}

# Sync downloads
@app.post("/sync/downloads")
async def sync_downloads(scholar_id: str, resource_ids: List[str]):
    auto_register_if_new(scholar_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    for rid in resource_ids:
        c.execute("INSERT OR IGNORE INTO scholar_downloads (scholar_id, resource_id) VALUES (?, ?)", (scholar_id, rid))
    conn.commit()
    conn.close()
    return {"status": "ok"}

# Restore profile
@app.get("/sync/restore/{scholar_id}")
async def restore_profile(scholar_id: str):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT action, resource_id, timestamp FROM activity_logs WHERE scholar_id = ? ORDER BY timestamp DESC LIMIT 10", (scholar_id,))
    recent = [{"action": r[0], "resource_id": r[1], "time": r[2]} for r in c.fetchall()]
    c.execute("SELECT resource_id FROM scholar_downloads WHERE scholar_id = ?", (scholar_id,))
    downloads = [r[0] for r in c.fetchall()]
    conn.close()
    return {"recent_activity": recent, "download_history": downloads}

# Register scholar
@app.post("/register")
async def register_scholar(scholar: ScholarReg):
    unique_suffix = str(uuid.uuid4())[:8].upper()
    full_id = f"LUMINA_01-{unique_suffix}"
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        pwd = scholar.password or "lumina2026"
        hashed = pwd_context.hash(pwd)
        c.execute("INSERT INTO scholars (id, name, hashed_password, reset_required) VALUES (?, ?, ?, 0)", (full_id, scholar.name, hashed))
        conn.commit()
        return {"id": full_id}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Registration error: {e}")
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
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        c = conn.cursor()
        pwd_to_check = pwd_context.hash("lumina2026")
        c.execute("UPDATE scholars SET hashed_password = ? WHERE id = ?", (pwd_to_check, scholar_id))
        conn.commit()
        conn.close()

    if not pwd_context.verify(data.password, pwd_to_check):
        raise HTTPException(status_code=401, detail="Invalid student credentials.")
        
    return {
        "status": "success",
        "scholar_id": scholar_id,
        "username": data.username,
        "reset_required": reset_req or 0
    }

# Student Password Change
@app.post("/student/change-password")
async def student_change_password(data: StudentChangePasswordRequest):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        hashed = pwd_context.hash(data.new_password)
        c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 0 WHERE id = ?", (hashed, data.scholar_id))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not change password: {e}")
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
        raise HTTPException(status_code=400, detail=f"Could not create subject: {e}")
    finally:
        conn.close()

# Teacher Profile Management API
def verify_teacher(request: Request):
    auth = request.headers.get("Authorization")
    cookie = request.cookies.get("lumina_session")
    if not cookie and not (auth and auth.startswith("Bearer ")):
        raise HTTPException(status_code=401, detail="Unauthorized: Teacher session required.")
    token = cookie or (auth.split(" ")[1] if auth else None)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT username FROM users WHERE username = ?", (token,))
    row = c.fetchone()
    conn.close()
    if not row:
        raise HTTPException(status_code=401, detail="Unauthorized: Invalid teacher session.")
    return token

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
    
    unique_suffix = str(uuid.uuid4())[:8].upper()
    full_id = f"LUMINA_01-T{unique_suffix}"
    c.execute("INSERT OR IGNORE INTO scholars (id, name) VALUES (?, ?)", (full_id, display_name))
    
    hashed_pwd = pwd_context.hash(teacher.password)
    try:
        c.execute("INSERT INTO users (username, hashed_password, name, department, scholar_id) VALUES (?, ?, ?, ?, ?)", (teacher.username, hashed_pwd, display_name, dept, full_id))
        conn.commit()
        return {"status": "success", "username": teacher.username, "name": display_name, "department": dept, "scholar_id": full_id}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not create teacher profile: {e}")
    finally:
        conn.close()

@app.delete("/teacher/profiles/{username}")
async def delete_teacher_profile(username: str, teacher_user: str = Depends(verify_teacher)):
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
async def get_scholars():
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

@app.get("/stats")
async def get_stats():
    total, used, free = shutil.disk_usage("/")
    battery_percent = 100
    try:
        if os.path.exists("/sys/class/power_supply/BAT0/capacity"):
            with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
                battery_percent = int(f.read().strip())
    except:
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
async def upload_resource(title: str, type: str, subject: str = "General", file: UploadFile = File(...), teacher_user: str = Depends(verify_teacher)):
    total, used, free = shutil.disk_usage("/")
    free_gb = free // (2**30)
    if free_gb < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")
    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename)
    file_path = os.path.join(UPLOAD_DIR, safe_filename)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
    with open(file_path, "wb") as buffer:
        buffer.write(await file.read())
    try:
        c.execute("INSERT INTO resources (title, file_path, type, subject) VALUES (?, ?, ?, ?)", (title, file_path, type, subject))
    except sqlite3.OperationalError:
        c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)", (title, file_path, type))
    conn.commit()
    conn.close()
    return {"status": "success"}

@app.post("/teacher/import-server-file")
async def import_server_file(filename: str, title: str, type: str, subject: str = "General", teacher_user: str = Depends(verify_teacher)):
    file_path = os.path.join(UPLOAD_DIR, filename)
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
        c.execute("SELECT hashed_password, name, department, scholar_id, reset_required FROM users WHERE username = ?", (username,))
        row = c.fetchone()
        reset_req = row[4] if row else 0
        if username == "admin":
            reset_req = 0
    except sqlite3.OperationalError:
        c.execute("SELECT hashed_password, username as name, 'General' as department, 'LUMINA_01-TEACHER' as scholar_id FROM users WHERE username = ?", (username,))
        row = c.fetchone()
        reset_req = 0
    conn.close()
    if not row or not pwd_context.verify(password, row[0]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials. Please try again.")
    
    response.set_cookie(key="lumina_session", value=username, httponly=True, max_age=86400, samesite="lax")
    return {
        "access_token": username,
        "token_type": "bearer",
        "username": username,
        "name": row[1] or username,
        "department": row[2] or "General",
        "scholar_id": row[3] or f"LUMINA_01-T_{username.upper()}",
        "is_teacher": True,
        "reset_required": reset_req or 0
    }

@app.post("/logout")
@app.get("/logout")
async def logout(response: Response):
    response.delete_cookie(key="lumina_session", path="/")
    return RedirectResponse(url="/welcome.html")

@app.post("/teacher/change-password")
async def change_password(data: ChangePasswordRequest, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT hashed_password FROM users WHERE username = ?", (data.username,))
    row = c.fetchone()
    if not row or not pwd_context.verify(data.old_password, row[0]):
        conn.close()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Incorrect current password.")
    new_hash = pwd_context.hash(data.new_password)
    c.execute("UPDATE users SET hashed_password = ?, reset_required = 0 WHERE username = ?", (new_hash, data.username))
    conn.commit()
    conn.close()
    return {"status": "success"}

@app.post("/teacher/disable-default-admin")
async def disable_default_admin(teacher_user: str = Depends(verify_teacher)):
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
    return {"status": "success"}

# Danger Zone Endpoints
@app.post("/teacher/scholars/reset-password/{scholar_id}")
async def teacher_reset_student_password(scholar_id: str, teacher_user: str = Depends(verify_teacher)):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        hashed = pwd_context.hash("lumina2026")
        c.execute("UPDATE scholars SET hashed_password = ?, reset_required = 1 WHERE id = ?", (hashed, scholar_id))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not reset student password: {e}")
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
        raise HTTPException(status_code=400, detail=f"Could not delete student account: {e}")
    finally:
        conn.close()

@app.post("/teacher/reset-password/{username}")
async def force_reset_teacher_password(username: str, teacher_user: str = Depends(verify_teacher)):
    if username == "admin" and teacher_user != "admin":
        raise HTTPException(status_code=400, detail="Only the main admin can reset the default admin account.")
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        hashed = pwd_context.hash("lumina2026")
        c.execute("UPDATE users SET hashed_password = ?, reset_required = 1 WHERE username = ?", (hashed, username))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Could not reset password: {e}")
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
        raise HTTPException(status_code=400, detail=f"Could not delete subject: {e}")
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
        raise HTTPException(status_code=400, detail=f"Could not delete resource: {e}")
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

# Mount static directories
app.mount("/files", StaticFiles(directory="uploads"), name="files")
app.mount("/static", StaticFiles(directory="static"), name="public_static")
