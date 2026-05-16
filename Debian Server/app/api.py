from fastapi import FastAPI, UploadFile, File, Depends, HTTPException, status, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
import os
import sqlite3
import shutil
import logging
import uuid
import re
import time
from pydantic import BaseModel
from typing import List
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

# --- Anti-Spam Rate Limiter ---
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.ip_records = {}

    async def dispatch(self, request: Request, call_next):
        # Protect open student endpoints
        protected_paths = ["/register", "/sync/activity", "/sync/downloads"]
        
        if any(request.url.path.startswith(p) for p in protected_paths):
            client_ip = request.client.host
            current_time = time.time()
            
            if client_ip in self.ip_records:
                # Remove requests older than 60 seconds
                self.ip_records[client_ip] = [t for t in self.ip_records[client_ip] if current_time - t < 60]
                
                # Limit: Max 20 requests per minute per IP
                if len(self.ip_records[client_ip]) >= 20:
                    logging.warning(f"BLOCKED: Rate limit exceeded by IP {client_ip}")
                    return Response(content="Rate limit exceeded", status_code=429)
                
                self.ip_records[client_ip].append(current_time)
            else:
                self.ip_records[client_ip] = [current_time]

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
    c.execute('CREATE TABLE IF NOT EXISTS activity_logs (scholar_id TEXT, action TEXT, resource_id TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP)')
    c.execute('CREATE TABLE IF NOT EXISTS scholar_downloads (scholar_id TEXT, resource_id TEXT, PRIMARY KEY(scholar_id, resource_id))')
    
    try:
        default_pwd = pwd_context.hash("lumina2026")
        c.execute("INSERT INTO users (username, hashed_password) VALUES (?, ?)", ("admin", default_pwd))
    except sqlite3.IntegrityError: pass
    
    # EDGE CASE: Force a WAL checkpoint on startup to prevent infinite disk bloat
    try:
        c.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    except sqlite3.OperationalError:
        pass # Reloader or other worker holds the lock, ignore
    
    conn.commit()
    conn.close()

init_db()

# Models
class TimeSync(BaseModel):
    current_time: str

class ScholarReg(BaseModel):
    name: str

class SyncActivity(BaseModel):
    scholar_id: str
    action: str
    resource_id: str

def auto_register_if_new(scholar_id: str, name: str = "Roaming Scholar"):
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT OR IGNORE INTO scholars (id, name) VALUES (?, ?)", (scholar_id, name))
    conn.commit()
    conn.close()

# --- Endpoints ---

@app.get("/system/stats")
@app.post("/system/sync-time")
async def sync_time(data: TimeSync):
    try:
        os.system(f"date -s '{data.current_time}'")
        logging.info(f"Time Synced: {data.current_time}")
        return {"status": "ok"}
    except: return {"status": "failed"}

# --- Captive Portal Interceptor ---
@app.get("/generate_204")
async def generate_204():
    """Tricks Android into thinking it has internet so it doesn't switch to cellular."""
    return Response(status_code=204)

@app.post("/sync/activity")
async def sync_activity(data: SyncActivity):
    auto_register_if_new(data.scholar_id)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("INSERT INTO activity_logs (scholar_id, action, resource_id) VALUES (?, ?, ?)", 
              (data.scholar_id, data.action, data.resource_id))
    conn.commit()
    conn.close()
    return {"status": "synced"}

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

@app.post("/register")
async def register_scholar(scholar: ScholarReg):
    unique_suffix = str(uuid.uuid4())[:8].upper()
    full_id = f"LUMINA_01-{unique_suffix}"
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    try:
        c.execute("INSERT INTO scholars (id, name) VALUES (?, ?)", (full_id, scholar.name))
        conn.commit()
        return {"id": full_id}
    except: raise HTTPException(status_code=400, detail="Error")
    finally: conn.close()

@app.get("/teacher/scholars")
async def get_scholars():
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT * FROM scholars")
    rows = c.fetchall()
    conn.close()
    return [{"id": r[0], "name": r[1]} for r in rows]

@app.get("/stats")
async def get_stats():
    total, used, free = shutil.disk_usage("/")
    battery_percent = 100
    try:
        if os.path.exists("/sys/class/power_supply/BAT0/capacity"):
            with open("/sys/class/power_supply/BAT0/capacity", "r") as f:
                battery_percent = int(f.read().strip())
    except: pass
    return {"storage_percent": (used / total) * 100, "battery_percent": battery_percent}

@app.get("/resources")
async def list_resources():
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    c.execute("SELECT * FROM resources")
    rows = c.fetchall()
    conn.close()
    return [{"id": r[0], "title": r[1], "url": f"/files/{os.path.basename(r[2])}", "type": r[3]} for r in rows]

@app.post("/teacher/upload")
async def upload_resource(title: str, type: str, file: UploadFile = File(...)):
    total, used, free = shutil.disk_usage("/")
    free_gb = free // (2**30)
    
    if free_gb < 2:
        logging.error("Upload rejected: Hub storage critically low (< 2GB free).")
        raise HTTPException(status_code=507, detail="Hub storage is full. Please delete older files before uploading.")

    safe_filename = re.sub(r'[^A-Za-z0-9_.-]', '_', file.filename)
    
    file_path = os.path.join(UPLOAD_DIR, safe_filename)
    
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    c = conn.cursor()
    
    # EDGE CASE: Overwrite Duplicate Files to save space
    c.execute("DELETE FROM resources WHERE file_path = ?", (file_path,))
    
    with open(file_path, "wb") as buffer: buffer.write(await file.read())
    c.execute("INSERT INTO resources (title, file_path, type) VALUES (?, ?, ?)", (title, file_path, type))
    conn.commit()
    conn.close()
    return {"status": "success"}

@app.get("/")
async def get_welcome():
    return FileResponse("static/welcome.html")

@app.get("/dashboard")
async def get_dashboard():
    return FileResponse("static/index.html")

app.mount("/files", StaticFiles(directory="uploads"), name="files")
app.mount("/static", StaticFiles(directory="static"), name="public_static")
