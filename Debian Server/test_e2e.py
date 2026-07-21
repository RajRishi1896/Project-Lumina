"""End-to-end test suite for Lumina Hub."""
import requests, json, sys
B = "http://127.0.0.1:8000"
p = f = 0
bugs = []

def login_user(user, pwd):
    r = requests.post(f"{B}/token", data={"username": user, "password": pwd})
    r.raise_for_status()
    return r.json()["access_token"]

def login_student(user, pwd):
    r = requests.post(f"{B}/student/token", json={"username": user, "password": pwd})
    r.raise_for_status()
    return r.json()["token"]

def T(name, fn):
    global p, f
    try:
        fn()
        p += 1
    except Exception as e:
        f += 1
        msg = str(e)[:200]
        bugs.append(f"{name}: {msg}")

# Get tokens
at = login_user("admin", "lumina2026")
tt = login_user("test_teacher", "lumina2026")
st = login_student("test_student", "Test12345678")
ah = {"Authorization": f"Bearer {at}"}
th = {"Authorization": f"Bearer {tt}"}
sh = {"Authorization": f"Bearer {st}"}

print("=== AUTH ===")
T("Admin whoami", lambda: None if requests.get(f"{B}/whoami", headers=ah).json()["role"] == "admin" else (_ for _ in ()).throw(Exception("wrong role")))
T("Teacher whoami", lambda: None if requests.get(f"{B}/whoami", headers=th).json()["role"] == "teacher" else (_ for _ in ()).throw(Exception("wrong role")))
T("Student profile", lambda: None if requests.get(f"{B}/student/profile", headers=sh).json().get("scholar_id") else (_ for _ in ()).throw(Exception("no scholar_id")))
T("Wrong password 401", lambda: (_ for _ in ()).throw(Exception(str(requests.post(f"{B}/token", data={"username":"admin","password":"wrong"}).status_code))) if requests.post(f"{B}/token", data={"username":"admin","password":"wrong"}).status_code == 200 else None)
T("Invalid token 401", lambda: (_ for _ in ()).throw(Exception(str(r.status_code))) if (r := requests.get(f"{B}/whoami", headers={"Authorization":"Bearer X"})).status_code != 401 else None)

print("=== PUBLIC ===")
T("Subjects", lambda: None if len(requests.get(f"{B}/subjects", headers=ah).json()) >= 1 else (_ for _ in ()).throw(Exception("empty")))
T("Grades", lambda: None if len(requests.get(f"{B}/grades", headers=ah).json()) >= 1 else (_ for _ in ()).throw(Exception("empty")))
T("Ping", lambda: requests.get(f"{B}/ping").json())
T("Healthz", lambda: None if requests.get(f"{B}/healthz").json()["status"] == "ok" else (_ for _ in ()).throw(Exception("bad")))
T("Stats", lambda: None if requests.get(f"{B}/stats", headers=ah).json().get("scholars") else (_ for _ in ()).throw(Exception("no scholars")))

print("=== TEACHER ===")
T("Teacher profile", lambda: None if requests.get(f"{B}/teacher/me", headers=th).json()["username"] == "test_teacher" else (_ for _ in ()).throw(Exception("wrong")))
T("Teacher scholars", lambda: requests.get(f"{B}/teacher/scholars", headers=th).json())
T("Teacher topics", lambda: requests.get(f"{B}/teacher/resource-topics", headers=th).json())

print("=== COURSE CRUD ===")
cid = [None]
def mk_course():
    r = requests.post(f"{B}/api/teacher/courses", json={"title":"E2E QA","subject":"General","grade":"8","language":"en"}, headers=th)
    r.raise_for_status()
    cid[0] = r.json()["id"]
T("Create course", mk_course)
T("Get course", lambda: None if requests.get(f"{B}/api/teacher/courses/{cid[0]}", headers=th).json()["title"] == "E2E QA" else (_ for _ in ()).throw(Exception("title")))
T("Update course", lambda: requests.put(f"{B}/api/teacher/courses/{cid[0]}", json={"title":"E2E QA v2"}, headers=th).json())
T("Add topic", lambda: requests.post(f"{B}/api/teacher/courses/{cid[0]}/topics", json={"title":"Ch1"}, headers=th).json())
T("List topics", lambda: None if len(requests.get(f"{B}/api/teacher/courses/{cid[0]}/topics", headers=th).json()) >= 1 else (_ for _ in ()).throw(Exception("empty")))
T("Course quiz", lambda: requests.post(f"{B}/api/teacher/courses/{cid[0]}/quiz", json={"title":"CQ","questions":[{"id":"q1","type":"mcq","question":"Q1?","options":["A","B"],"correct_answer":0}],"time_limit_minutes":5,"pass_threshold":50}, headers=th).json())
T("Publish", lambda: requests.post(f"{B}/api/teacher/courses/{cid[0]}/publish", headers=th).json())

print("=== STUDENT LMS ===")
T("Browse courses", lambda: None if requests.get(f"{B}/api/courses", headers=sh).json()["total"] >= 1 else (_ for _ in ()).throw(Exception("0")))
def enroll():
    courses = requests.get(f"{B}/api/courses", headers=sh).json()["items"]
    cid2 = courses[0]["id"]
    requests.post(f"{B}/api/courses/{cid2}/enroll", headers=sh)
T("Enroll", enroll)
def progress():
    courses = requests.get(f"{B}/api/courses", headers=sh).json()["items"]
    requests.get(f"{B}/api/courses/{courses[0]['id']}/progress", headers=sh)
T("Progress", progress)
T("Analytics", lambda: requests.get(f"{B}/student/analytics", headers=sh).json())
T("Weekly", lambda: requests.get(f"{B}/student/weekly-breakdown", headers=sh).json())

print("=== UPLOAD ===")
def upload_quiz():
    r = requests.post(f"{B}/teacher/upload-quiz", json={"title":"E2E Quiz","time_limit_minutes":10,"pass_threshold":60,"questions":[{"type":"mcq","text":"Q?","options":["A","B"],"correct_answer":0}]}, headers=th)
    d = r.json()
    if d.get("status") != "success": raise Exception(f"status={d}")
T("Upload quiz", upload_quiz)
T("List resources", lambda: None if len(requests.get(f"{B}/resources", headers=th).json()) >= 1 else (_ for _ in ()).throw(Exception("empty")))

print("=== LOCALIZATION ===")
for lang in ["en", "hi", "kn", "fr"]:
    def check_lang(l=lang):
        r = requests.get(f"{B}/static/lang/{l}.json")
        d = r.json()
        if len(d) < 100: raise Exception(f"{len(d)} keys")
    T(f"Lang {lang}", check_lang)

print("=== STATIC PAGES ===")
s = requests.Session()
s.post(f"{B}/token", data={"username":"admin","password":"lumina2026"})
for pg in ["index", "courses", "students", "manage-content", "manage-danger", "manage-settings", "welcome"]:
    def check_page(p=pg):
        r = s.get(f"{B}/static/{p}.html", timeout=5)
        if r.status_code != 200: raise Exception(f"HTTP {r.status_code}")
    T(f"Page {pg}", check_page)

print("=== SECURITY ===")
T("SQL injection", lambda: (_ for _ in ()).throw(Exception("passed")) if requests.post(f"{B}/token", data={"username":"admin'OR'1'='1","password":"x"}).status_code == 200 else None)
T("Student->teacher 403", lambda: None if requests.get(f"{B}/teacher/me", headers=sh).status_code == 403 else (_ for _ in ()).throw(Exception("not 403")))
T("Teacher->admin 403", lambda: None if requests.get(f"{B}/admin/log", headers=th).status_code in (401, 403) else (_ for _ in ()).throw(Exception("not 401/403")))

print(f"\n{'='*50}")
print(f"PASS: {p} | FAIL: {f}")
if bugs:
    print("\nBUGS:")
    for b in bugs:
        print(f"  [!] {b}")
print(f"{'='*50}")
sys.exit(1 if f > 0 else 0)
