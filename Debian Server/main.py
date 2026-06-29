"""Lumina EduMesh Hub — Uvicorn launcher.

This module is the entry point for the EduMesh Hub server. It starts the
FastAPI application (defined in app.api) via Uvicorn on 0.0.0.0:8000.
Supports optional self-signed SSL via --ssl-certfile and --ssl-keyfile args.
"""

import os
import argparse
import logging
import uvicorn
from app.api import app

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Lumina EduMesh Hub")
    parser.add_argument("--ssl-certfile", default=None, help="Path to SSL certificate file")
    parser.add_argument("--ssl-keyfile", default=None, help="Path to SSL key file")
    args = parser.parse_args()

    ssl_certfile = args.ssl_certfile or os.environ.get("SSL_CERTFILE")
    ssl_keyfile = args.ssl_keyfile or os.environ.get("SSL_KEYFILE")

    # Auto-detect default cert paths relative to Debian Server directory
    if not ssl_certfile or not ssl_keyfile:
        default_cert = os.path.join(os.path.dirname(__file__), "data", "server.pem")
        default_key = os.path.join(os.path.dirname(__file__), "data", "server.key")
        if os.path.isfile(default_cert) and os.path.isfile(default_key):
            ssl_certfile = default_cert
            ssl_keyfile = default_key

    ssl_kwargs = {}
    if ssl_certfile and ssl_keyfile:
        ssl_kwargs["ssl_certfile"] = ssl_certfile
        ssl_kwargs["ssl_keyfile"] = ssl_keyfile
        logging.info(f"Starting with SSL (cert={ssl_certfile})")
    else:
        logging.info("Starting without SSL (no cert files found)")

    logging.info("Starting EduMesh Hub...")
    # Single worker — SQLite WAL mode supports concurrent readers across
    # processes but multi-worker adds complexity (each worker has its own
    # in-memory state).  20-worker thread pool inside the single process
    # handles 250 concurrent students without issues.
    workers = int(os.environ.get("UVICORN_WORKERS", "1"))
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False, workers=workers, timeout_keep_alive=60, **ssl_kwargs)
