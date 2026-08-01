"""Login as admin and trigger ZIM re-import."""
import urllib.request
import json
import sys

BASE = "http://localhost:8000"

def api(method, path, data=None, token=None):
    url = BASE + path
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()}")
        return None

# Login as admin
print("Logging in as admin...")
login_resp = api("POST", "/api/auth/login", {"username": "admin", "password": "lumina2026"})
if not login_resp:
    print("Login failed!")
    sys.exit(1)

token = login_resp.get("access_token") or login_resp.get("token")
if not token:
    print(f"No token in response: {login_resp}")
    sys.exit(1)
print(f"Got token: {token[:20]}...")

# Trigger import-local-zim
print("\nTriggering import-local-zim for ZIM-b9a13790b828.zim...")
print("(This will take a while for 19M articles...)")
result = api("POST", f"/api/zim/teacher/import-local-zim?filename=ZIM-b9a13790b828.zim", token=token)
if result:
    print(f"Done! {json.dumps(result, indent=2)}")
else:
    print("Import failed!")
