"""Background ZIM HTML cache cleaner.

Periodically removes the oldest cached HTML pages (generated from ZIM
archives) when the total number exceeds the configured ``max_pages``
limit. Runs on a daemon thread started at server startup.
"""

import os
import json
import time
import logging
from threading import Thread

# Directory where ZIM HTML pages are stored (must match zim_handler)
ZIM_PAGES_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'zim_pages')
os.makedirs(ZIM_PAGES_DIR, exist_ok=True)

_CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data', 'zim_cache_config.json')


def _get_max_pages() -> int:
    """Read max_pages from the ZIM cache config JSON, defaulting to 500."""
    try:
        with open(_CONFIG_PATH) as f:
            cfg = json.load(f)
        return int(cfg.get('max_pages', 500))
    except Exception:
        return 500


def _clean_old_pages():
    """Enforce the hard cache page limit.

    The most recently saved pages are kept; the oldest files are removed
    when the total number of cached HTML pages exceeds the configured
    ``max_pages`` value (default 500).
    """
    try:
        max_pages = _get_max_pages()
    except Exception as e:
        logging.error(f"Failed to read max_pages: {e}")
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
            logging.error(f"Failed to delete {old_file}: {e}")


_cleaner_started = False


def start_zim_auto_cleaner(interval_seconds: int = 3600):
    """Start a background daemon thread that prunes the ZIM cache.

    The cleaner runs indefinitely every ``interval_seconds`` (default
    1 hour). It is safe to call multiple times — only the first call
    starts the thread.

    Args:
        interval_seconds: Seconds between cleanup runs (default 3600).

    Returns:
        The spawned :class:`threading.Thread` instance, or ``None`` if
        the cleaner was already running.
    """
    global _cleaner_started
    if _cleaner_started:
        return
    _cleaner_started = True

    def _run():
        while True:
            _clean_old_pages()
            time.sleep(interval_seconds)

    Thread(target=_run, daemon=True).start()
