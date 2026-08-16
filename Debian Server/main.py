"""Lumina EduMesh Hub -- Uvicorn launcher.

This module is the entry point for the EduMesh Hub server. It starts the
FastAPI application (defined in app.api) via Uvicorn on 0.0.0.0:8000.
"""

import os
import sys
import argparse
import logging
import uvicorn
from app.api import app


def _detect_hub_ip():
    """Return the LAN IP of the hotspot interface (10.42.0.1 preferred)."""
    import socket
    # If we're the hub, return the known hotspot IP
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.42.0.1", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        pass
    # Fallback: scan interfaces
    try:
        import subprocess
        out = subprocess.check_output(
            ["ip", "-4", "addr", "show", "scope", "global"],
            text=True, timeout=3
        )
        for line in out.splitlines():
            if "10.42.0." in line:
                return "10.42.0.1"
        # No hotspot IP found, return first non-loopback
        for line in out.splitlines():
            if "inet " in line:
                return line.split()[1].split("/")[0]
    except Exception:
        pass
    return "localhost"


def _print_startup_banner():
    """Print connection info + QR code to the terminal."""
    ip = _detect_hub_ip()
    url = f"http://{ip}:8000"

    try:
        import qrcode
        qr = qrcode.QRCode(box_size=1, border=1)
        qr.add_data(f"WIFI:T:WPA;S:Lumina Hub;P:lumina2026;;")
        qr.make(fit=True)
        qr_print = []
        for row in qr.get_matrix():
            qr_print.append("".join("\u2588\u2588" if c else "  " for c in row))
        qr_block = "\n".join(qr_print)
    except ImportError:
        qr_block = "(pip install qrcode for QR code)"

    os.system("cls" if os.name == "nt" else "clear")
    print()
    print("=" * 60)
    print("   LUMINA HUB")
    print("=" * 60)
    print()
    print(f"   Server:    {url}")
    print(f"   Hotspot:   Lumina Hub")
    print(f"   Password:  lumina2026")
    print()
    print("   Scan QR to connect to WiFi:")
    print()
    for line in qr_block.splitlines():
        print(f"     {line}")
    print()
    print("   Then open in browser:")
    print(f"   {url}")
    print()
    print("=" * 60)
    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Lumina EduMesh Hub")
    parser.add_argument("--no-banner", action="store_true", help="Skip startup banner")
    args = parser.parse_args()

    if not args.no_banner:
        _print_startup_banner()

    logging.info("Starting EduMesh Hub...")
    workers = int(os.environ.get("UVICORN_WORKERS", "1"))
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False, workers=workers, timeout_keep_alive=60)
