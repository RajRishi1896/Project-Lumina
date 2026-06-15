"""Lumina EduMesh Hub — FastAPI application entry point.
All route handlers are in app/routers/.
"""
import os
import logging
import asyncio
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.middleware import RateLimitMiddleware
from app.encryption import EncryptedAPIRoute
from app.database import DB_PATH

# Logging
os.makedirs("data", exist_ok=True)
log_handler = RotatingFileHandler('data/hub.log', maxBytes=5*1024*1024, backupCount=3)
logging.basicConfig(handlers=[log_handler], level=logging.INFO, format='%(asctime)s - %(message)s')


@asynccontextmanager
async def lifespan(application: FastAPI):
    """Startup/shutdown lifecycle for background services.

    On startup: run DB init, ZIM auto-cleaner, task queue, mDNS beacon,
    and session pruning background tasks.
    On shutdown: stop task queue and mDNS beacon.
    """
    # --- STARTUP ---
    from app.database import init_db, DB_PATH
    import sqlite3

    await asyncio.to_thread(init_db)
    def _ensure_admin():
        conn = sqlite3.connect(DB_PATH, timeout=5.0)
        try:
            cur = conn.cursor()
            cur.execute('UPDATE users SET role = "admin" WHERE username = "admin"')
            conn.commit()
        finally:
            conn.close()
    await asyncio.to_thread(_ensure_admin)

    from app.zim_auto_cleaner import start_zim_auto_cleaner
    from app.task_queue import start as start_task_queue, stop as stop_task_queue, register_handler
    from app.thumb_worker import generate_thumbnail

    start_zim_auto_cleaner(interval_seconds=3600)
    await start_task_queue(max_workers=2)
    register_handler("generate_thumbnail", generate_thumbnail)
    try:
        from app.discovery import MeshBeacon
        beacon = MeshBeacon(port=8000)
        beacon.start()
        application.state.beacon = beacon
    except Exception:
        pass

    # Session pruning background task
    async def prune_sessions():
        while True:
            await asyncio.sleep(3600)
            try:
                conn = sqlite3.connect(DB_PATH)
                conn.execute("DELETE FROM sessions WHERE last_accessed IS NOT NULL AND last_accessed < datetime('now', '-7 days')")
                conn.execute("DELETE FROM sessions WHERE last_accessed IS NULL AND created_at < datetime('now', '-7 days')")
                conn.execute("DELETE FROM refresh_tokens WHERE expires_at < datetime('now') OR used = 1")
                conn.execute("DELETE FROM persistent_keys WHERE expires_at < datetime('now')")
                conn.commit()
                conn.close()
            except Exception:
                pass
    prune_task = asyncio.create_task(prune_sessions())

    yield  # application runs here

    # --- SHUTDOWN ---
    prune_task.cancel()
    try:
        await prune_task
    except asyncio.CancelledError:
        pass
    await stop_task_queue()
    state = getattr(application, 'state', None)
    if state is not None:
        beacon = getattr(state, 'beacon', None)
        if beacon is not None:
            try:
                beacon.stop()
            except Exception:
                pass


app = FastAPI(
    title="Lumina EduMesh Hub",
    description="Offline-first educational mesh network hub. Manages students, teachers, resources, study analytics, and content distribution for the EduMesh Android client.",
    version="1.0.0",
    contact={"name": "EduMesh Team", "url": "https://github.com/anomalyco/opencode"},
    license_info={"name": "MIT", "identifier": "MIT"},
    openapi_tags=[
        {"name": "Auth", "description": "Authentication and session management for students, teachers, and admins."},
        {"name": "Student", "description": "Student sync, analytics, profile management, and icon upload."},
        {"name": "Scholars", "description": "Scholar listing, password reset, and account management."},
        {"name": "Teacher Students", "description": "Teacher-facing student listing, analytics, and teacher profile management."},
        {"name": "Academics", "description": "Subject and grade management."},
        {"name": "Resources", "description": "Resource CRUD, upload, catalog, and ZIM import."},
        {"name": "Media", "description": "Media streaming with HTTP Range support and thumbnail generation."},
        {"name": "Administration", "description": "Default admin toggles, admin/teacher/student CRUD."},
        {"name": "Passwords", "description": "Password change, force-change, and admin password reset."},
        {"name": "Admin Logs", "description": "Audit logs, admin settings, and log download."},
        {"name": "System Stats", "description": "Hub statistics, health endpoint, and time sync."},
        {"name": "System", "description": "Health checks, captive portal, static file serving, and user identity."},
    ],
    lifespan=lifespan,
)
app.router.route_class = EncryptedAPIRoute

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiter
app.add_middleware(RateLimitMiddleware)

# Security headers
@app.middleware("http")
async def add_security_headers(request, call_next):
    """Attach security-related HTTP headers to every response.

    Adds X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, and
    Cache-Control headers to harden client-side security.
    """
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Cache-Control"] = "no-cache, private"
    return response

# Import routers
from app.routers.auth import router as auth_router
from app.routers.student import router as student_router
from app.routers.scholars import router as scholars_router
from app.routers.teacher_students import router as teacher_students_router
from app.routers.academics import router as academics_router
from app.routers.resources import router as resources_router
from app.routers.media import router as media_router
from app.routers.administration import router as administration_router
from app.routers.passwords import router as passwords_router
from app.routers.admin_logs import router as admin_logs_router
from app.routers.system_stats import router as system_stats_router
from app.routers.system import router as system_router
from zim_handler import router as zim_router

app.include_router(auth_router)
app.include_router(student_router)
app.include_router(scholars_router)
app.include_router(teacher_students_router)
app.include_router(academics_router)
app.include_router(resources_router)
app.include_router(media_router)
app.include_router(administration_router)
app.include_router(passwords_router)
app.include_router(admin_logs_router)
app.include_router(system_stats_router)
app.include_router(system_router)
app.include_router(zim_router, prefix="/zim")

# Static file mounts (must be after routes)
app.mount("/static", StaticFiles(directory="static", html=True), name="static")
app.mount("/files", StaticFiles(directory="uploads"), name="files")
