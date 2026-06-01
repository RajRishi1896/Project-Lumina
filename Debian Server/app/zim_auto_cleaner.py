import os
import time
import threading
from datetime import datetime

# Import the settings helper for cache size limit
from lib.zim_settings import get_max_pages

# Directory where ZIM HTML pages are stored (must match zim_handler)
ZIM_PAGES_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'zim_pages')
os.makedirs(ZIM_PAGES_DIR, exist_ok=True)

def _clean_old_pages():
    """Enforce the hard cache page limit.
    The most recently saved pages are kept; the oldest files are removed
    when the total number of cached HTML pages exceeds the configured
    `max_pages` value (default 500)."""
    try:
        max_pages = get_max_pages()
    except Exception as e:
        print(f"[ZIM Cleaner] Failed to read max_pages: {e}")
        return
    files = [f for f in os.listdir(ZIM_PAGES_DIR) if f.endswith('.html')]
    if len(files) <= max_pages:
        return
    # Sort files by modification time (oldest first)
    files.sort(key=lambda f: os.path.getmtime(os.path.join(ZIM_PAGES_DIR, f)))
    excess = len(files) - max_pages
    for i in range(excess):
        old_file = os.path.join(ZIM_PAGES_DIR, files[i])
        try:
            os.remove(old_file)
        except Exception as e:
            print(f"[ZIM Cleaner] Failed to delete {old_file}: {e}")

_cleaner_lock = threading.Lock()
_cleaner_started = False

def start_zim_auto_cleaner(interval_seconds: int = 3600):
    """Start a background thread that cleans the ZIM cache every `interval_seconds`.
    Default is 1 hour.
    """
    global _cleaner_started
    with _cleaner_lock:
        if _cleaner_started:
            return
        _cleaner_started = True
    def _run():
        while True:
            _clean_old_pages()
            time.sleep(interval_seconds)
    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
    return thread
