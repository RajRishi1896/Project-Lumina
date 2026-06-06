"""ZIM cache configuration backed by a JSON file.

Provides thread-safe getters and setters for two settings stored in
``data/zim_cache_config.json``:
    - ``retention_days`` (default 7)
    - ``max_pages`` (default 500)
"""

import json
import os
from threading import Lock

CONFIG_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'zim_cache_config.json')
_lock = Lock()


def _ensure_config():
    """Create the config directory and default JSON file if they don't exist."""
    if not os.path.exists(os.path.dirname(CONFIG_PATH)):
        os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if not os.path.isfile(CONFIG_PATH):
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump({"retention_days": 7, "max_pages": 500}, f)


def get_retention_days() -> int:
    """Return the number of days ZIM pages are retained before cleanup.

    Returns:
        The configured retention days (default 7).
    """
    with _lock:
        _ensure_config()
        try:
            with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return 7
    return int(data.get('retention_days', 7))


def set_retention_days(days: int):
    """Set the number of days to retain ZIM pages.

    Args:
        days: New retention period in days.
    """
    with _lock:
        _ensure_config()
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
        data['retention_days'] = days
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f)


def get_max_pages() -> int:
    """Return the maximum number of ZIM HTML pages allowed in cache.

    Returns:
        The configured max page limit (default 500).
    """
    with _lock:
        _ensure_config()
        try:
            with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return 500
    return int(data.get('max_pages', 500))


def set_max_pages(limit: int):
    """Set the maximum number of ZIM HTML pages to keep in cache.

    Args:
        limit: New maximum page count.
    """
    with _lock:
        _ensure_config()
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
        data['max_pages'] = limit
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f)
