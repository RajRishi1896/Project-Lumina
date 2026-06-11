"""Lumina EduMesh Hub — FastAPI application entry point.
All route handlers are in app/routers/.
"""
import os
import logging
import asyncio
from logging.handlers import RotatingFileHandler
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.middleware import RateLimitMiddleware
from app.encryption import EncryptedAPIRoute
from app.database import init_db, _startup_time, DB_PATH

# Logging
os.makedirs("data", exist_ok=True)
log_handler = RotatingFileHandler('data/hub.log', maxBytes=5*1024*1024, backupCount=3)
logging.basicConfig(handlers=[log_handler], level=logging.INFO, format='%(asctime)s - %(message)s')

# Run DB init (synchronous at startup) before creating the app
init_db()

app = FastAPI(
    title="Lumina EduMesh Hub",
    description="Offline-first educational mesh network hub. Manages students, teachers, resources, study analytics, and content distribution for the EduMesh Android client.",
    version="1.0.0",
    contact={"name": "EduMesh Team", "url": "https://github.com/anomalyco/opencode"},
    license_info={"name": "MIT", "identifier": "MIT"},
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

# Startup / shutdown events
from app.zim_auto_cleaner import start_zim_auto_cleaner
from app.task_queue import start as start_task_queue, stop as stop_task_queue, register_handler
from app.thumb_worker import generate_thumbnail

@app.on_event("startup")
async def startup_services():
    """Start background services on application startup.

    Launches the ZIM auto-cleaner (hourly interval), the background
    task queue (2 workers), and the mDNS/DNS-SD discovery beacon so
    the hub is discoverable on the local network.
    """
    start_zim_auto_cleaner(interval_seconds=3600)
    await start_task_queue(max_workers=2)
    register_handler("generate_thumbnail", generate_thumbnail)
    try:
        from app.discovery import MeshBeacon
        beacon = MeshBeacon(port=8000)
        beacon.start()
        app.state.beacon = beacon
    except Exception:
        pass

@app.on_event("startup")
async def start_pruning():
    """Start a background task that prunes expired sessions and tokens.

    Runs every hour, deleting sessions inactive for 30 days, expired
    refresh tokens, and expired persistent keys.
    """
    async def prune_sessions():
        """Remove stale sessions, refresh tokens, and persistent keys from the database."""
        while True:
            await asyncio.sleep(3600)
            try:
                import sqlite3
                conn = sqlite3.connect(DB_PATH)
                conn.execute("DELETE FROM sessions WHERE last_accessed IS NOT NULL AND last_accessed < datetime('now', '-30 days')")
                conn.execute("DELETE FROM sessions WHERE last_accessed IS NULL AND created_at < datetime('now', '-30 days')")
                conn.execute("DELETE FROM refresh_tokens WHERE expires_at < datetime('now')")
                conn.execute("DELETE FROM persistent_keys WHERE expires_at < datetime('now')")
                conn.commit()
                conn.close()
            except Exception:
                pass
    asyncio.create_task(prune_sessions())

@app.on_event("shutdown")
async def shutdown_services():
    """Clean up background services on application shutdown.

    Stops the mDNS/DNS-SD discovery beacon and the background task
    queue if they were started.
    """
    await stop_task_queue()
    if hasattr(app.state, 'beacon'):
        try:
            app.state.beacon.stop()
        except Exception:
            pass

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
