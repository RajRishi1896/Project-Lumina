import json
import os
from threading import Lock

CONFIG_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'zim_cache_config.json')
_lock = Lock()

def _ensure_config():
    if not os.path.exists(os.path.dirname(CONFIG_PATH)):
        os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    if not os.path.isfile(CONFIG_PATH):
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump({"retention_days": 7, "max_pages": 500}, f)

def get_retention_days() -> int:
    _ensure_config()
    with _lock:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    return int(data.get('retention_days', 7))

def set_retention_days(days: int):
    _ensure_config()
    with _lock:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
        data['retention_days'] = days
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f)

def get_max_pages() -> int:
    _ensure_config()
    with _lock:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    return int(data.get('max_pages', 500))

def set_max_pages(limit: int):
    _ensure_config()
    with _lock:
        with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
        data['max_pages'] = limit
        with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f)
