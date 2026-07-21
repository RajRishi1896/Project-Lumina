"""Extended E2E test suite -- edge cases, error paths, delete, duplicate, unicode."""
import requests, json, sys, os
B = "http://127.0.0.1:8000"
p = f = 0
bugs = []

def T(name, fn):
    global p, f
    try:
        fn()
        p += 1
    except Exception as e:
        f += 1
        msg = str(e)[:200]
        bugs.append(f"{name}: {msg}")

at = requests.post(f"{B}/token", data={"username":"admin","password":"lumina2026"}).json()["access_token"]
tt = requests.post(f"{B}/token", data={"username":"test_teacher","password":"lumina2026"}).json()["access_token"]
st = requests.post(f"{B}/student/token", json={"username":"test_student","password":"Test12345678"}).json()["token"]
ah = {"Authorization": f"Bearer {at}"}
th = {"Authorization": f"Bearer {tt}"}
sh = {"Authorization": f"Bearer {st}"}

print("=== EDGE CASES ===")
T("Duplicate grade", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.post(f"{B}/grades", json={"name":"Grade 8"}, headers=ah)).status_code not in (400, 409, 200) else None)
T("Delete grade nonexistent", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.delete(f"{B}/grades/nonexistent", headers=ah)).status_code not in (400, 404) else None)
T("Empty quiz upload", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.post(f"{B}/teacher/upload-quiz", json={"title":"","questions":[]}, headers=th)).status_code != 400 else None)
T("Quiz no questions", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.post(f"{B}/teacher/upload-quiz", json={"title":"X","questions":[]}, headers=th)).status_code != 400 else None)
T("Quiz unicode title", lambda: requests.post(f"{B}/teacher/upload-quiz", json={"title":"Quiz \u0915\u093f\u0924\u093e\u092c \u0627\u0644\u0639\u0631\u0628\u064a\u0629","questions":[{"type":"mcq","text":"Q?","options":["A","B"],"correct_answer":0}]}, headers=th).json())
T("Quiz emoji title", lambda: requests.post(f"{B}/teacher/upload-quiz", json={"title":"Quiz \U0001f389","questions":[{"type":"mcq","text":"Q?","options":["A","B"],"correct_answer":0}]}, headers=th).json())
T("Quiz long title", lambda: requests.post(f"{B}/teacher/upload-quiz", json={"title":"A"*200,"questions":[{"type":"mcq","text":"Q?","options":["A","B"],"correct_answer":0}]}, headers=th).json())
T("Quiz special chars", lambda: requests.post(f"{B}/teacher/upload-quiz", json={"title":"Quiz <script>alert(1)</script>","questions":[{"type":"mcq","text":"Q?","options":["A","B"],"correct_answer":0}]}, headers=th).json())

print("\n=== DELETE OPERATIONS ===")
# Create then delete a course
cr = requests.post(f"{B}/api/teacher/courses", json={"title":"Delete Me","subject":"General","grade":"8","language":"en"}, headers=th).json()
delid = cr["id"]
T("Delete course", lambda: requests.delete(f"{B}/api/teacher/courses/{delid}", headers=th).json())
T("Deleted course is archived", lambda: (_ for _ in ()).throw(Exception(f"published={r.json().get('published')}")) if (r := requests.get(f"{B}/api/teacher/courses/{delid}", headers=th)).json().get("published") != -1 else None)

# Create and delete subject
requests.post(f"{B}/teacher/subjects", json={"name":"DeleteSubj"}, headers=ah)
T("Delete subject", lambda: requests.delete(f"{B}/teacher/subjects/DeleteSubj", headers=ah))

print("\n=== AUTH EDGE CASES ===")
T("Double login", lambda: (requests.post(f"{B}/token", data={"username":"admin","password":"lumina2026"}).json(), requests.post(f"{B}/token", data={"username":"admin","password":"lumina2026"}).json()))
T("Concurrent logins admin", lambda: [requests.post(f"{B}/token", data={"username":"admin","password":"lumina2026"}).json() for _ in range(3)])
T("Empty username", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.post(f"{B}/token", data={"username":"","password":"lumina2026"})).status_code not in (400, 401, 422) else None)
T("Empty password", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.post(f"{B}/token", data={"username":"admin","password":""})).status_code not in (400, 401, 422) else None)

print("\n=== SYSTEM ===")
T("System stats", lambda: requests.get(f"{B}/system/stats", headers=ah).json())
T("Sync time", lambda: requests.post(f"{B}/system/sync-time", json={"server_time":"2026-01-01T00:00:00Z"}, headers=ah).json())
T("Default admin status", lambda: requests.get(f"{B}/teacher/default-admin-status", headers=ah).json())
T("Whoami with cookie", lambda: (s := requests.Session(), s.post(f"{B}/token", data={"username":"admin","password":"lumina2026"}), s.get(f"{B}/whoami").json()))

print("\n=== TEACHER CRUD ===")
T("Teacher list", lambda: requests.get(f"{B}/teachers", headers=ah).json())
T("Teacher profiles", lambda: requests.post(f"{B}/teacher/profiles", headers=ah).json())
T("Update teacher name", lambda: requests.post(f"{B}/teacher/profile/name", json={"name":"Test Teacher Updated"}, headers=th).json())

# Resources
T("Resources list", lambda: requests.get(f"{B}/resources", headers=th).json())
T("API catalog", lambda: requests.get(f"{B}/api/catalog", headers=th).json())
T("File list", lambda: requests.get(f"{B}/api/files", headers=th).json())
T("Upload limits", lambda: requests.get(f"{B}/api/limits", headers=th).json())

print("\n=== ZIM ===")
T("ZIM archives", lambda: requests.get(f"{B}/zim/archives", headers=th).json())
T("ZIM articles", lambda: requests.get(f"{B}/zim/articles", headers=th).json())
T("ZIM search", lambda: requests.get(f"{B}/zim/search?q=test", headers=th).json())

print("\n=== COURSE STUDENT FLOW ===")
# Publish a course and test full student flow
courses = requests.get(f"{B}/api/teacher/courses", headers=th).json()
published = [c for c in courses if c.get("published")]
if published:
    cid = published[0]["id"]
    T("Student course detail", lambda: requests.get(f"{B}/api/courses/{cid}", headers=sh).json())
    T("Student topics", lambda: requests.get(f"{B}/api/teacher/courses/{cid}/topics", headers=th).json())
    # Test course resources
    T("Teacher course resources", lambda: requests.get(f"{B}/api/teacher/courses/{cid}", headers=th).json())

print("\n=== SEARCH & FILTER ===")
T("Search resources", lambda: requests.get(f"{B}/resources?search=Quiz", headers=th).json())
T("Filter by subject", lambda: requests.get(f"{B}/resources?subject=General", headers=th).json())

print(f"\n{'='*50}")
print(f"PASS: {p} | FAIL: {f}")
if bugs:
    print("\nBUGS:")
    for b in bugs:
        print(f"  [!] {b}")
print(f"{'='*50}")
sys.exit(1 if f > 0 else 0)
