"""Lumina EduMesh Hub -- FastAPI application entry point.
All route handlers are in app/routers/.
"""
import os
import sys
import logging
import asyncio
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.async_db import db_fetch, db_run

# Logging
os.makedirs("data", exist_ok=True)
log_handler = RotatingFileHandler('data/hub.log', maxBytes=5*1024*1024, backupCount=3)
console_handler = logging.StreamHandler(sys.stdout)
logging.basicConfig(
    handlers=[log_handler, console_handler],
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
)
logging.getLogger("lumina.middleware").setLevel(logging.INFO)

_startup_time = __import__("time").time()


@asynccontextmanager
async def lifespan(application: FastAPI):
    """Startup/shutdown lifecycle for background services.

    On startup: run DB init, ZIM auto-cleaner, and session pruning.
    On shutdown: cancel background tasks.
    """
    # --- STARTUP ---
    from app.database import init_db

    await asyncio.to_thread(init_db)

    from app.database import ensure_media_columns
    await ensure_media_columns()

    from app.routers.system_stats import detect_wifi_caps
    await detect_wifi_caps()

    from app.zim_auto_cleaner import start_zim_auto_cleaner

    start_zim_auto_cleaner(interval_seconds=3600)

    # Auto-reindex ZIM archives missing from zim_articles (e.g. manual SQL re-link)
    # Runs as a background task with a startup delay so the server is ready first.
    async def _auto_reindex_zim():
        await asyncio.sleep(8)
        logging.info("Auto-reindex: started")
        try:
            rows = await db_fetch(
                "SELECT id, zim_path, title FROM zim_archives "
                "WHERE NOT EXISTS (SELECT 1 FROM zim_articles WHERE archive_id=zim_archives.id)"
            )
            if not rows:
                logging.info("Auto-reindex: no archives need reindexing")
                return
            from app.routers.resource_zim import _reindex_zim_articles
            logging.info(f"Auto-reindex: {len(rows)} archive(s) with no articles")
            for aid, path, title in rows:
                if not path or not os.path.isfile(path):
                    logging.warning(f"Auto-reindex: skipping {aid} -- ZIM file not at {path}")
                    continue
                logging.info(f"Auto-reindex: indexing {aid} ({title})...")
                try:
                    r = await asyncio.to_thread(_reindex_zim_articles, path, aid, title or "")
                    logging.info(f"Auto-reindex: {aid} done ({r['article_count']} articles)")
                except Exception as e:
                    logging.error(f"Auto-reindex: {aid} failed: {e}")
            logging.info("Auto-reindex: complete")
        except Exception as e:
            logging.error(f"Auto-reindex scan failed: {e}")
    reindex_task = asyncio.create_task(_auto_reindex_zim())

    # Session pruning background task
    async def prune_sessions():
        while True:
            await asyncio.sleep(3600)
            try:
                def _prune_sessions(conn):
                    conn.execute("DELETE FROM sessions WHERE last_accessed IS NOT NULL AND last_accessed < datetime('now', '-7 days')")
                    conn.execute("DELETE FROM sessions WHERE last_accessed IS NULL AND created_at < datetime('now', '-7 days')")
                    conn.execute("DELETE FROM refresh_tokens WHERE expires_at < datetime('now') OR used = 1")
                    conn.execute("DELETE FROM persistent_keys WHERE expires_at < datetime('now')")
                    conn.commit()
                await db_run(_prune_sessions)
                from app.dependencies import _session_cache
                _session_cache.clear()
            except Exception:
                logging.exception("Session pruning failed")
    prune_task = asyncio.create_task(prune_sessions())

    # mDNS discovery -- optional, never blocks startup if zeroconf is absent
    from app.discovery import HubDiscovery
    hub_discovery = HubDiscovery()
    await hub_discovery.start()

    # Daily log retention pruning
    from app.audit import _prune_logs_now
    async def prune_admin_logs():
        while True:
            await asyncio.sleep(86400)
            try:
                await asyncio.to_thread(_prune_logs_now)
            except Exception:
                logging.exception("Admin log pruning failed")
    log_prune_task = asyncio.create_task(prune_admin_logs())

    # Hub federation -- hourly refresh of paired peers' resource catalogs
    from app.peer_refresh import peer_refresh_loop
    peer_refresh_task = asyncio.create_task(peer_refresh_loop(interval_seconds=3600))

    yield  # application runs here

    # --- SHUTDOWN ---
    await hub_discovery.stop()
    peer_refresh_task.cancel()
    try:
        await peer_refresh_task
    except asyncio.CancelledError:
        pass
    reindex_task.cancel()
    try:
        await reindex_task
    except asyncio.CancelledError:
        pass
    log_prune_task.cancel()
    try:
        await log_prune_task
    except asyncio.CancelledError:
        pass
    prune_task.cancel()
    try:
        await prune_task
    except asyncio.CancelledError:
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
        {"name": "Federation", "description": "Hub-to-hub pairing, signed peer endpoints, and peer resource sharing."},
    ],
    lifespan=lifespan,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://lumina.hub:8000", "http://10.42.0.1:8000", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request ID, structured logging, and rate limiting
from app.middleware import RequestIDMiddleware, RequestLoggingMiddleware, RateLimitMiddleware

app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(RequestIDMiddleware)
app.add_middleware(RateLimitMiddleware, default_limit=200, default_window=60)

# Security headers
@app.middleware("http")
async def add_security_headers(request, call_next):
    """Attach security-related HTTP headers to every response.

    Adds X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, and
    Cache-Control headers to harden client-side security.
    """
    from app.metrics import record_request
    client_ip = request.client.host if request.client else "unknown"
    record_request(client_ip)

    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    path = request.url.path
    if path.startswith("/static/") or path.startswith("/files/"):
        if response.status_code >= 400:
            response.headers["Cache-Control"] = "no-store"
        else:
            response.headers["Cache-Control"] = "public, max-age=300"
    else:
        response.headers["Cache-Control"] = "no-cache, private"
    return response

# Import routers
from app.routers.auth import router as auth_router
from app.routers.student import router as student_router
from app.routers.scholars import router as scholars_router
from app.routers.teacher_students import router as teacher_students_router
from app.routers.academics import router as academics_router
from app.routers.resources import router as resources_router
from app.routers.resource_zim import router as resource_zim_router
from app.routers.media import router as media_router
from app.routers.administration import router as administration_router
from app.routers.passwords import router as passwords_router
from app.routers.admin_logs import router as admin_logs_router
from app.routers.system_stats import router as system_stats_router
from app.routers.system import router as system_router
from app.routers.teacher_courses import router as teacher_courses_router
from app.routers.teacher_course_resources import router as teacher_course_resources_router
from app.routers.teacher_quizzes import router as teacher_quizzes_router
from app.routers.teacher_topics import router as teacher_topics_router
from app.routers.teacher_similar import router as teacher_similar_router
from app.routers.teacher_flashcards import router as teacher_flashcards_router
from app.routers.teacher_quiz_resources import router as teacher_quiz_resources_router
from app.routers.student_courses import router as student_courses_router
from app.routers.federation import router as federation_router
from zim_handler import router as zim_router

app.include_router(auth_router)
app.include_router(student_router)
app.include_router(scholars_router)
app.include_router(teacher_students_router)
app.include_router(academics_router)
app.include_router(resources_router)
app.include_router(resource_zim_router)
app.include_router(media_router)
app.include_router(administration_router)
app.include_router(passwords_router)
app.include_router(admin_logs_router)
app.include_router(system_stats_router)
app.include_router(system_router)
app.include_router(teacher_courses_router)
app.include_router(teacher_course_resources_router)
app.include_router(teacher_quizzes_router)
app.include_router(teacher_topics_router)
app.include_router(teacher_similar_router)
app.include_router(teacher_flashcards_router)
app.include_router(student_courses_router)
app.include_router(teacher_quiz_resources_router)
app.include_router(federation_router)
app.include_router(zim_router, prefix="/zim")

# Static file mounts (must be after routes)
app.mount("/static", StaticFiles(directory="static", html=True), name="static")
app.mount("/files", StaticFiles(directory="uploads"), name="files")
