"""Check that all lang/*.json files have the same keys as en.json."""
import json
import sys
from pathlib import Path

LANG_DIR = Path("Debian Server/static/lang")
en_keys = set(json.loads((LANG_DIR / "en.json").read_text()).keys())

exit_code = 0
for lang in ["hi", "kn", "fr"]:
    file = LANG_DIR / f"{lang}.json"
    keys = set(json.loads(file.read_text()).keys())
    missing = en_keys - keys
    extra = keys - en_keys
    if missing:
        print(f"[FAIL] {lang}: missing {len(missing)} keys: {sorted(missing)[:10]}...")
        exit_code = 1
    if extra:
        print(f"[FAIL] {lang}: {len(extra)} extra keys not in en.json: {sorted(extra)[:10]}...")
        exit_code = 1
    if not missing and not extra:
        print(f"[OK] {lang}: all {len(keys)} keys match en.json")

sys.exit(exit_code)
