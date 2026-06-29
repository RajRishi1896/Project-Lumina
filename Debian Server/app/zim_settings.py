"""ZIM cache configuration backed by a JSON file.

Provides thread-safe getters and setters for two settings stored in
``data/zim_cache_config.json``:
    - ``retention_days`` (default 7)
    - ``max_pages`` (default 500)
"""

import json
import os

CONFIG_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'zim_cache_config.json')
DEFAULT_CONFIG = {"retention_days": 7, "max_pages": 500}


def _ensure_config():
    """Create the config directory and default JSON file if they don't exist."""
    if not os.path.exists(os.path.dirname(CONFIG_PATH)):
        os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if not os.path.isfile(CONFIG_PATH):
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(DEFAULT_CONFIG, f)


def config_get(key: str, default):
    _ensure_config()
    try:
        with open(CONFIG_PATH) as f:
            cfg = json.load(f)
        return cfg.get(key, default)
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return default


def config_set(key: str, value):
    try:
        with open(CONFIG_PATH) as f:
            cfg = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        cfg = {}
    cfg[key] = value
    with open(CONFIG_PATH, 'w') as f:
        json.dump(cfg, f)


def get_retention_days() -> int:
    return int(config_get('retention_days', DEFAULT_CONFIG["retention_days"]))


def set_retention_days(days: int):
    config_set('retention_days', days)


def get_max_pages() -> int:
    return int(config_get('max_pages', DEFAULT_CONFIG["max_pages"]))


def set_max_pages(limit: int):
    config_set('max_pages', limit)
