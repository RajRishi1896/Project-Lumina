"""Lumina EduMesh Hub — Uvicorn launcher.

This module is the entry point for the EduMesh Hub server. It starts the
FastAPI application (defined in app.api) via Uvicorn on 0.0.0.0:8000.
"""

import logging
import uvicorn
from app.api import app

if __name__ == "__main__":
    logging.info("Starting EduMesh Hub...")
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False, timeout_keep_alive=60)
