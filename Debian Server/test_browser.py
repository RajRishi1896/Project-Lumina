"""Browser-equivalent runtime verification via HTTP."""
import requests

B = 'http://127.0.0.1:8000'
s = requests.Session()
s.post(f'{B}/token', data={'username': 'admin', 'password': 'lumina2026'})

print("=== REDIRECT CHAIN TEST ===")
for page in ['courses.html', 'students.html', 'manage-content.html']:
    r = s.get(f'{B}/{page}', allow_redirects=False)
    loc = r.headers.get('Location', 'none')
    print(f"  GET /{page} -> {r.status_code} Location={loc}")
    if r.status_code in (301, 302):
        r2 = s.get(f'{B}{loc}', allow_redirects=False)
        loc2 = r2.headers.get('Location', 'none')
        print(f"    -> GET {loc} -> {r2.status_code} Location={loc2} len={len(r2.text)}")

print("\n=== ALL PAGES (follow redirects) ===")
pages = ['index.html', 'welcome.html', 'courses.html', 'students.html',
         'student-detail.html', 'manage-content.html', 'manage-help.html',
         'manage-danger.html', 'manage-settings.html', 'error.html']
for page in pages:
    r = s.get(f'{B}/{page}', allow_redirects=True, timeout=5)
    has_app = 'app-content' in r.text
    has_i18n = 'data-i18n' in r.text
    has_lumina = 'lumina' in r.text.lower()
    print(f"  {page}: {r.status_code} final={r.url} len={len(r.text)} app={has_app} i18n={has_i18n}")

print("\n=== SPA NAV TEST (courses without .html) ===")
for path in ['courses', 'students', 'manage-content', 'manage-settings', 'manage-danger', 'manage-help', 'student-detail']:
    r = s.get(f'{B}/{path}', allow_redirects=True, timeout=5)
    has_app = 'app-content' in r.text
    print(f"  /{path}: {r.status_code} final={r.url} len={len(r.text)} app={has_app}")

print("\n=== JS/CSS/LANG ASSETS ===")
for asset in ['css/lumina.css', 'js/lumina.js', 'lang/en.json', 'lang/hi.json', 'lang/kn.json', 'lang/fr.json',
              'assets/logo-dark.svg', 'assets/logo-light.svg', 'assets/hero-dark.svg', 'assets/hero-light.svg']:
    r = requests.get(f'{B}/static/{asset}', timeout=5)
    print(f"  {asset}: {r.status_code} len={len(r.text)}")

print("\n=== STATIC FILE MOUNTS ===")
r = s.get(f'{B}/static/courses', allow_redirects=False)
print(f"  /static/courses: {r.status_code}")
r = s.get(f'{B}/static/courses.html', allow_redirects=False)
print(f"  /static/courses.html: {r.status_code} Location={r.headers.get('Location', 'none')}")

print("\n=== UNAUTHENTICATED ACCESS ===")
s2 = requests.Session()
for page in ['welcome.html', 'index.html', 'courses.html', 'error.html']:
    r = s2.get(f'{B}/{page}', allow_redirects=True, timeout=5)
    print(f"  /{page} (no auth): {r.status_code} len={len(r.text)}")

print("\n=== AUTH API ENDPOINTS ===")
for endpoint in ['/whoami', '/api/teacher/courses', '/api/teacher/scholars', '/grades', '/teacher/subjects']:
    r = s.get(f'{B}{endpoint}', timeout=5)
    print(f"  {endpoint}: {r.status_code} type={r.headers.get('content-type', 'unknown')[:30]}")
