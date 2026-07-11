# Implementation Plan

Phase 1 (audit fixes, performance, i18n, theme) is complete. This plan covers
Phase 2 — features and infrastructure for beta production test.

## Execution Order

### 1. Download Counts
Add a download counter to each resource so teachers can see which resources
students actually use.

**Server:**
- Add `downloads INTEGER DEFAULT 0` to resources table via schema migration
  in `database.py`
- In `student.py:sync_downloads`, increment after INSERT OR IGNORE:
  `UPDATE resources SET downloads = downloads + 1 WHERE id = ?`
- Include `downloads` in `resources.py:list_resources` response
- Add `downloads` field to `CatalogResourceResponse` in `models.py`

**Frontend:**
- `manage-content.html`: add a "Downloads" column to the resource table

**Files:** `database.py`, `student.py`, `resources.py`, `models.py`, `manage-content.html`

### 2. Teacher Resource Notes
Teachers can attach a text note to any resource. Notes display in Flutter
resource detail and web resource table tooltip.

**Server:**
- Add `notes TEXT DEFAULT NULL` to resources table via schema migration
- New PATCH endpoint `PATCH /resources/{id}/notes` accepts `{"notes": "..."}`
- Include `notes` in `resources.py:list_resources` response
- Add `notes` field to `CatalogResourceResponse`

**Frontend:**
- `resource_detail_page.dart`: section titled "Teacher Notes" below metadata
  (visible only when notes is non-empty)
- `manage-content.html`: muted text column on resource row

**Files:** `database.py`, `resources.py`, `models.py`, `resource_detail_page.dart`, `manage-content.html`

### 3. SPA Client-Side Navigation
Eliminate white flash between page loads. ~100 lines JS, zero server changes.

**In `lumina.js`:**
- `navigateTo(url)` — fetch full HTML via `fetch()`, parse with `DOMParser`,
  swap `#app-content` innerHTML, `history.pushState()`, re-run
  `applyLanguage()` + `initCurrentPage()`
- `initCurrentPage()` — switch on URL path to call the right init function
- `window.onpopstate` — handle back/forward via `navigateTo(url, false)`
- Sidebar `<a>` clicks intercepted: `preventDefault()` → `navigateTo(url)`

**In each of 9 HTML pages:**
- Wrap variable content in `<div id="app-content">...</div>`
- Replace `DOMContentLoaded` inline script with `window._pageInit = fn`
- Page init functions registered globally in `lumina.js`

**Files:** `lumina.js`, `index.html`, `manage-content.html`, `manage-security.html`,
`students.html`, `student-detail.html`, `manage-help.html`, `manage-danger.html`,
`manage-settings.html`, `welcome.html`

### 4. Weakest Student Flagging
Surface students with zero activity in N days on the students list.

**Server — new route in `teacher_students.py`:**
```
GET /teacher/at-risk-students?days=3
```
Query returns students with no activity in N days.

**Frontend:**
- `students.html`: red left border + warning icon + tooltip "Last studied X days ago"
- `student-detail.html`: yellow warning card at top

**Files:** `teacher_students.py`, `students.html`, `student-detail.html`, `lumina.js`

### 5. Sort-by for Students Tab
Sort dropdown on the students list.

**Frontend — `students.html`:**
- Sort options: Name, Study Time (high/low), Last Active, Saved Resources
- Client-side sort of existing card data

**Files:** `students.html`, `lumina.js`

### 6. Tests
Run before beta prod: `pytest Debian\ Server/tests/ && flutter test`

**Server tests — `Debian Server/tests/`:**
```
tests/
  conftest.py     # TestClient fixture + test DB setup/teardown
  test_api.py     # 6 test functions
```

- `conftest.py`:
  - Override `app.database.DB_PATH` to `data/test.db` before app import
  - Create test DB with same schema as production
  - Seed demo data: 1 admin, 1 teacher, 3 students, 3 resources, activity records
  - Teardown: remove `data/test.db` after session

- `test_api.py` — 6 test functions:

| Test | Assertion |
|------|-----------|
| `test_health` | `GET /api/health` → 200 + `"status": "ok"` |
| `test_login_admin` | `POST /login` with admin creds → 200 + token |
| `test_wrong_password` | `POST /login` with bad password → 401 |
| `test_protected_route` | `GET /static/manage-content` without session → error |
| `test_rate_limiting` | 11 rapid failed logins → 11th returns 429 |
| `test_list_resources` | `GET /resources` → 200 + returns seeded resources |

**Flutter — keep existing 1 smoke test.** Validates `LuminaApp` renders a `MaterialApp`.
Catching widget rendering errors would require mocking Dio, DB, connectivity
(~100× more test code, marginal value).

**Dependencies:** Add `pytest` and `httpx` to `requirements.txt`

### 7. .gitignore
Add explicit entry for test DB: `data/test.db`

### 8. Assignments / Quizzes
Fully scoped in `LMS Docs/LMS_Implementation_Plan.md` — data model (courses,
quiz_attempts), API endpoints, web quiz builder, Flutter quiz player with
offline-first design.

Refer to that document. This item tracks integration into the delivery timeline.

---

## Acceptance Criteria
- Server starts and all endpoints respond correctly
- `dart analyze lib/` — 0 errors, 0 warnings
- `pytest tests/` — 6/6 pass
- `flutter test` — 1/1 pass
- Manage-content shows download counts + teacher notes
- Students page shows at-risk flagging + sort-by
- No page flash on sidebar navigation
- Flutter resource detail shows teacher notes

## Recommended Commit Sequencing
1. Download Counts
2. Teacher Resource Notes (server + web)
3. Teacher Resource Notes (Flutter display)
4. SPA Client-Side Navigation
5. Weakest Student Flagging
6. Sort-by for Students Tab
7. Tests
8. Assignments / Quizzes
