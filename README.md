<p align="center">
  <img src="Debian%20Server/static/assets/Horizontal Transparent Lightmode Icon.svg" alt="Project Lumina logo">
</p>

<h1 align="center">Project Lumina · EduMesh Hub</h1>

<p align="center"><em>An offline-first educational mesh for rural schools</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi" alt="FastAPI">
  <img src="https://img.shields.io/badge/SQLite-WAL-003B57?logo=sqlite" alt="SQLite WAL">
  <img src="https://img.shields.io/badge/Offline--First-✓-brightgreen" alt="Offline-First">
  <img src="https://img.shields.io/badge/WCAG_AA-✓-brightgreen" alt="WCAG AA">
  <img src="https://img.shields.io/badge/i18n-6_Languages-important" alt="i18n">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

---

An offline-first educational mesh for rural schools. A repurposed laptop runs a WiFi hotspot, a FastAPI content server, and a captive portal; students access textbooks, videos, and interactive content from Android phones, with no internet connection required.

## Table of Contents

- [Overview](#overview)
- [Who It Is For](#who-it-is-for)
- [Architecture](#architecture)
- [Features](#features)
- [API / Interface Overview](#api--interface-overview)
- [Data Model](#data-model)
- [Performance Data](#performance-data)
- [Engineering Trade-offs](#engineering-trade-offs)
- [Tech Stack](#tech-stack)
- [Setup and Deployment](#setup-and-deployment)
- [Roadmap](#roadmap)
- [Documentation](#documentation)
- [Contributing and Credits](#contributing-and-credits)
- [License](#license)

---

## Overview

Project Lumina is a first-year college project: an offline-first learning platform for schools where broadband, stable power, and student-owned devices cannot be assumed. One low-cost server laptop hosts all content and services. Android phones on a local hotspot consume the content through a Flutter app that remains fully usable when the hub is unreachable.

Two independent codebases form the system: a Flutter Android client (`EduMesh-Android/`, 66 Dart files) and a FastAPI server (`Debian Server/`, 22 router modules plus a ZIM handler). They share no code, no dependencies, and no toolchain. They communicate over plain HTTP on the local network, with the laptop acting as gateway at the static address `10.42.0.1`.

**Why it exists.** Existing LMS platforms assume always-on broadband and one device per student. The environment this targets provides neither. The project instead assumes nothing: no internet, one laptop for an entire school, content delivered by USB stick, and progress synchronized in the brief window a phone is near the hub.

**Current maturity.** The system is feature-complete for single-classroom and school-lab deployment. It passes a 38-test pytest suite, `dart analyze` at 0 errors and 0 warnings, and has run end-to-end on emulators and development hardware. What remains unvalidated: a load test at the stated 250-concurrent-student target, and a sustained multi-week field deployment on the production hub laptop. The concurrency figures below are design targets validated only at small scale.

---

## Who It Is For

**Primary users**

- **Rural schools** where one repurposed laptop serves a whole class. The laptop runs the hub server, the WiFi hotspot, and the captive portal.
- **Students sharing devices** who need profile switching, offline browsing, and progress that survives WiFi drops.
- **Teachers in low-infrastructure regions** who upload PDFs and videos once and assign them without worrying about connectivity.
- **NGOs and community centers** deploying offline learning kits in areas without reliable power or internet.

**Primary use cases**

| Use case | How it works |
|---|---|
| Browse and search content | Catalog cached in local SQLite; works with the hub offline |
| Download for offline study | One-at-a-time queue with exponential backoff and atomic `.part` rename |
| Structured learning | Courses with ordered topics, teacher-authored quizzes, per-student progress |
| Spaced repetition | SM-2 flashcard decks reviewed in the app, authored on the web dashboard |
| Analytics for teachers | Study time, subject minutes, and download history synced from phones |
| Content delivery at scale | Kiwix ZIM archives served lazily from the binary; downloads inline assets for offline rendering |

---

## Features

### Student app (Flutter)

**Offline infrastructure**

- **Catalog cache.** `CatalogService` mirrors the full resource catalog into local SQLite inside a single transaction, so a mid-sync dropout cannot leave partial data. Offline browsing, searching, and filtering work without the hub. Undownloaded resources render as ghost items (0.45 to 0.5 opacity) with a distinct background, so students can see what is not available.
- **Download queue.** `DownloadQueue` processes one file at a time with exponential backoff (`3 * (1 << retryCount)`: 3, 6, 12, 24, 48 seconds). Files download to a `.part` name and rename on completion, so a partial download never surfaces as a finished file. Pending downloads persist to the `pending_downloads` table and resume on reconnect.
- **Mutation queue.** `MutationQueue` persists profile updates and activity events when the hub is unreachable and replays them in order on reconnect, dropping only after three retries. All student-state mutations route through this queue; project convention forbids direct fire-and-forget calls.
- **Connectivity monitor.** Hybrid detection: `connectivity_plus` platform events for instant notification, plus a 30-second HTTP `/ping` heartbeat with a 4-second timeout. Reconnect flushes pending downloads, mutations, and the catalog cache.

**Content experience**

- **Course browser and player.** Browse, enroll, and track progress through structured courses. Courses contain resources organized into ordered topics with teacher-authored quizzes.
- **Flashcards.** SM-2 spaced-repetition decks reviewed in the app; teachers create decks and review submissions on the web dashboard.
- **Video with picture-in-picture.** `MiniPlayerController` is a process-wide singleton. Leaving full-screen playback continues in a mini overlay; closing it disposes both `VideoPlayerController` and `ChewieController`. Video streams via `/api/stream/` with HTTP Range support for seeking.
- **PDF viewer.** `pdfx` with pinch-to-zoom and zoom buttons (0.25x steps). Page position persists to `SharedPreferences`; a 6-column page grid provides rapid navigation.
- **ZIM article browser.** Kiwix archives are searchable server-side with a 1 to 500 article cap per query (a deliberate OOM guard for 1 GB phones). Articles render in-app; downloaded articles inline all assets as data URIs for fully offline rendering.
- **Search recommendations.** An on-device scorer ranks resources locally: +3 for matching grade, +2 for a previously accessed subject, +1 for the most-viewed resource type; the top 6 surface as "Recommended for You".

**Resilience**

- **Triple data fallback.** Every resource lookup tries the server API, then the `CatalogService` SQLite cache, then the local downloads table.
- **Staleness detection.** Before opening a local file the app compares cached mtime with the server and re-downloads when outdated.
- **Token renewal.** Three-tier session fallback (session token, 7-day refresh token, 365-day persistent key); the Dio interceptor walks the tiers on 401/403 before logging out.
- **Keystore recovery.** `flutter_secure_storage` keys are invalidated when a user removes their lock-screen PIN, which otherwise crash-loops the app. The read site catches the `PlatformException`, calls `deleteAll()` to clear corrupted state, and forces a fresh login.

**UX and accessibility**

- 6 languages (English, Hindi, Kannada, French, Tamil, Telugu): 410 ARB keys with ICU plurals in Flutter, 728 JSON keys on web, identical key sets across all six files.
- All fonts bundled as `.ttf` (Noto Sans per script); `GoogleFonts` is a fallback only.
- Every tappable element meets the 48x48px minimum touch target; icon-only buttons carry `Tooltip` or `Semantics` labels.
- `PopScope` double-back-to-exit with a 2-second window (first press shows a SnackBar with an Exit button).
- 4-tab bottom navigation (Dashboard, Browse, Saved, Profile), always visible.

### Hub server (FastAPI)

171 routes across 22 router modules plus `zim_handler.py`, covering auth, student sync, teacher analytics, course management, content CRUD, media streaming, account management, passwords, audit logs, system health, and ZIM serving.

| Router | Lines | Purpose |
|---|---|---|
| `auth.py` | 343 | Login, register, token management |
| `student.py` | 377 | Sync, analytics, profile, icons |
| `student_courses.py` | 573 | Course browsing, enrollment, progress, quizzes |
| `teacher_courses.py` | 323 | Course CRUD, publish toggle, similar suggestions |
| `teacher_students.py` | 274 | Student listing, teacher analytics |
| `teacher_course_resources.py` | 460 | Course resource upload, ZIP import/export |
| `teacher_topics.py` | 216 | Course topic CRUD, ordering |
| `teacher_quizzes.py` | 144 | Quiz creation and editing |
| `teacher_similar.py` | 95 | Similar course links |
| `teacher_flashcards.py` | 388 | Flashcard deck CRUD, review, submissions |
| `teacher_quiz_resources.py` | 252 | Standalone quiz resources (not course-bound) |
| `academics.py` | 607 | Subjects, grades, resource topics CRUD |
| `resources.py` | 238 | Resource CRUD, upload, soft-delete |
| `resource_catalog.py` | 204 | Read-only catalog/detail/files/limits + shared cache |
| `resource_zim.py` | 493 | ZIM upload, processing, deletion |
| `media.py` | 336 | HTTP Range streaming, thumbnails |
| `administration.py` | 206 | Account management |
| `passwords.py` | 109 | Password change, reset |
| `admin_logs.py` | 220 | Audit log, settings, log download |
| `system_stats.py` | 572 | Hub stats, health, time sync |
| `system.py` | 188 | Health check, captive portal, static serving |
| `scholars.py` | 99 | Scholar listing, reset, delete |

Operational details:

- **Soft-delete lifecycle.** Deleting a resource sets `status = 'deleted'` plus `deleted_at` (30-day recycle bin); an hourly purge hard-deletes file and row. Deleted resources vanish from catalog and search but stay reachable by direct ID.
- **Rate limiting.** Per-IP token bucket at 200 requests/minute (configurable), exempting localhost, static assets, `/ping`, and ZIM GETs; ZIM uploads are separately capped.
- **Content standards.** Uploads validate against a controlled subject taxonomy and grades 1 to 13 (0 reserved for pre-primary, 13 for bridging and exam prep), require source and license metadata, and reject duplicates on `title + subject + grade + language + resource_type` with a `409` response plus an explicit `force_upload` override.
- **Audit logging.** Admin actions and resource status transitions append to `data/admin_actions.log` with UTC timestamps and acting user IDs; retention is configurable.
- **No external dependencies.** The server starts and serves every endpoint with no internet connection; `setup_hub.sh` provisioning is idempotent and completes offline after the initial package pass.

### Web dashboard

An 11-page vanilla HTML/CSS/JS teacher and admin dashboard served from the hub: dashboard, courses, students, student detail, content manager, flashcards, danger zone, settings, help, welcome (captive portal), error. Role-based access is enforced server-side on each page; students only reach the captive portal. All 11 pages are fully translated with client-side debounced search inputs.

---

## API / Interface Overview

171 routes grouped by prefix. Student- and teacher-facing routes live under `/api`, `/student`, `/teacher`; captive-portal and health routes are public.

| Prefix | Routes | What they do |
|---|---|---|
| `/api/*` | 74 | Catalog, resources, ZIM articles, uploads, streaming |
| `/teacher/*` | 31 | Course CRUD, topics, quizzes, resources, students, flashcards, similar |
| `/student/*` | 21 | Sync (study time, downloads, subjects), analytics, profile, icons |
| `/zim/*` | 6 | ZIM page/asset/thumbnail serving, article search |
| `/system/*` | 6 | Health, ping, captive portal, whoami, static serving |
| `/grades` | 4 | Grade taxonomy CRUD |
| `/resources`, `/sync`, `/logout` | 5 | Resource detail, student sync, session logout |
| `/docs`, `/redoc`, `/openapi.json` | 4 | FastAPI interactive docs |
| `/`, `/welcome`, `/dashboard`, `/index.html`, captive-portal probes | 20 | Web pages + OS captive-portal detection URLs |

Notable endpoint behaviours:

- **Streaming.** Video files are served through `/api/stream/` with HTTP Range support (206 Partial Content) so students can seek without full download. The server does not transcode; target phones decode in hardware.
- **Auth.** JWT-style session tokens with the three-tier renewal described above; newly registered students are forced through a password change. Passwords are bcrypt-hashed server-side; the offline-only login path uses a separate local SHA-256 credential that never shares the server hash.
- **ZIM serving.** HTML from `/zim/page` has asset paths rewritten to `/zim/asset` endpoints that read lazily from the `.zim` binary; article search is capped at 500 results. An hourly auto-cleaner prunes archives by LRU policy against `zim_cache_config.json`.

The full OpenAPI spec is served at `/docs` when the server is running.

---

## Data Model

Server: a single SQLite file at `data/hub.db` in WAL mode. All access goes through `app/async_db.py` helpers, which run queries in a thread pool (`asyncio.to_thread`) so the event loop stays free; `db_conn()` is reserved for multi-statement transactions.

**Accounts and auth**

| Table | Purpose |
|---|---|
| `users` | Teacher/admin accounts (username, bcrypt hash, role) |
| `scholars` | Student accounts (id, name, grade, username) |
| `sessions` / `refresh_tokens` / `persistent_keys` | Three-tier token tables |
| `settings` | Key/value hub settings |

**Content**

| Table | Purpose |
|---|---|
| `resources` | Uploaded files (title, subject, grade, language, type, source, license, status) |
| `subjects`, `grades` | Taxonomy used across resources and courses |
| `resource_topics` | Topic tags for standalone resources |
| `zim_archives` / `zim_articles` | ZIM archive and per-article metadata |

**Courses and quizzes**

| Table | Purpose |
|---|---|
| `courses`, `course_resources`, `course_progress` | Course structure + per-student progress |
| `topics` | Course topic ordering |
| `similar_courses` | Teacher-linked similar course suggestions |
| `quiz_attempts`, `quiz_best_scores` | Quiz results per student |
| `flashcard_decks`, `flashcards`, `flashcard_submissions` | SM-2 deck/card/submission state |

**Analytics**

| Table | Purpose |
|---|---|
| `weekly_study` | Per-student study seconds + streak days |
| `study_sessions` | Start/end/duration of study sessions |
| `subject_minutes` | Per-student per-subject minutes |
| `scholar_downloads` | Download history |
| `activity_logs` | Per-student event log (references student IDs, never names) |
| `student_bookmarks` | Student-saved resources |

Client: the Flutter app mirrors catalog and progress state in its own local SQLite (schema version 17, migration chain from v2). Tables include `resources`, `catalog`, `activity`, `bookmarks`, `downloads`, `pending_downloads`, `pending_mutations`, course tables, `quiz_cache`, `zim_archives_local`, `zim_articles_local`, and flashcard tables (`flashcard_decks_local`, `flashcard_cards_local`, `flashcard_reviews_local`, `flashcard_submissions_local`).

---

## Performance Data

### Targets vs. measured (development hardware)

Measured on a MediaTek MT6739 phone (1 GB RAM, Android 8) and an Intel Celeron N4020 server (4 GB RAM, 5400 RPM HDD).

| Metric | Target | Measured |
|---|---|---|
| Cold start to interactive | ≤ 4 s | 3.2 s |
| Dashboard catalog load (cached) | ≤ 800 ms | 450 ms |
| Resource list scroll (60 fps) | 0 jank frames | 0 jank |
| SQLite query (single resource) | ≤ 50 ms | 12 ms |
| APK size (release, ARM-only) | ≤ 25 MB | 22 MB |
| First video frame (streaming) | - | 1.1 s |

### Server under 50 concurrent students (syncing every 60 s)

| Metric | Result |
|---|---|
| Average response time | < 200 ms |
| Catalog listing (200 resources) | 45 ms |
| PDF thumbnail generation (10 MB file) | 350 ms (background) |
| Video thumbnail generation (1080p, 15 min) | 4.2 s (background) |

**Caveats.** The concurrency design target is 250 students without degraded response times, but no load test at that scale has been run; these figures come from development-scale sessions on the hardware named above. A repeatable benchmark harness is not yet published in the repo. Project conventions require a documented mitigation plan for any change that regresses a target by more than 20%.

---

## Engineering Trade-offs

**SQLite over PostgreSQL.** WAL-mode SQLite handles the write patterns of a classroom on a Celeron with 2 GB RAM and is zero-configuration for non-DBA teachers. The cost is single-writer concurrency, which sets a practical ceiling around 100+ students before migration becomes necessary. The DB layer is isolated behind `async_db.py` so a PostgreSQL migration is a contained change rather than a rewrite.

**500-article ZIM search cap.** Kiwix archives hold hundreds of thousands of articles; loading them all would OOM a 1 GB phone. Capping search at 500 results guarantees the app never crashes on query, at the cost of requiring multiple queries for deep research across large archives.

**Test coverage vs. offline reliability.** Development time went to offline reliability (mutation queue, download atomicity, Keystore recovery) rather than test volume. The resulting suite is 38 tests across 5 files (API, flashcards, quiz integrity, resource security) plus a Flutter smoke test: enough to make refactoring safe, not exhaustive. This was the correct order for v1; the suite is the planned growth area.

**`.part` rename on FAT32.** The download rename is not atomic on FAT32/exFAT, the filesystems on most cheap SD cards. The `.part` convention still prevents corrupted files from masquerading as complete, and a crash mid-rename leaves at most one orphaned file. Writing to a temp directory and moving has the same fundamental limitation on these filesystems.

**Federation removed.** Hub-to-hub peer federation (mDNS discovery, hourly peer sync, a `/peer/*` API) shipped in 2026-08 and was pulled after review concluded that single-node architecture was the honest scope for the target hardware. Phone-to-phone sharing (ShareServer) remains. The recorded lesson: peer sync added failure modes without a demonstrated classroom need.

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Mobile app | Flutter 3.x (Dart) | Android student client |
| HTTP client | Dio 5 | API calls, interceptors, retry |
| Local database | SQLite via `sqflite` | Offline cache, pending queues (schema v17) |
| Secure storage | `flutter_secure_storage` | Session tokens, credentials |
| Server | FastAPI (Python) | REST API, background tasks, static files |
| Server DB | SQLite WAL mode | Analytics, sessions, content metadata |
| Auth (server) | bcrypt + JWT-style session tokens | Password hashing, role-based access |
| Auth (offline client) | SHA-256 (local-only) | Offline credential verification |
| Thumbnails | ffmpeg + PyMuPDF | Video black-intro skip, PDF 0.3x scale |
| Video streaming | HTTP Range requests | 206 Partial Content for seek |
| Captive portal | dnsmasq + NetworkManager | DNS hijack to hub welcome page |
| Frontend | Vanilla HTML/CSS/JS | Teacher/admin dashboard (11 pages) |
| i18n (Flutter) | ARB files + `flutter gen-l10n` | 6 languages, ICU plurals, 410 keys |
| i18n (Web) | JSON lang files + `lumina.js` | 6 languages, 728 keys each |

All 23 direct dependencies of the Flutter app are listed in `pubspec.yaml`; all server dependencies in `requirements.txt`. No CDN-served assets and no external APIs appear in the offline-critical path.

---

## Setup and Deployment

### Development

```bash
# Server (Terminal 1)
cd "Debian Server"
python main.py                       # Uvicorn on 0.0.0.0:8000

# Student app (Terminal 2)
cd "EduMesh-Android"
flutter run                          # Connects via lumina.hub -> 10.42.0.1:8000
```

The default admin login is `admin` / `lumina2026`.

### Production (Debian laptop)

```bash
cd /opt/lumina/"Debian Server"
sudo ./setup_hub.sh                  # Idempotent. Run once.
sudo systemctl start lumina-hub      # Or: sudo systemctl restart lumina-hub
```

`setup_hub.sh` provisions system dependencies, a Python venv, UFW firewall rules, dnsmasq captive-portal DNS via NetworkManager, systemd services, lid-close sleep disable, nightly reboot, and unlimited file descriptors. It completes without internet after the initial package-install pass.

### APK deployment

```bash
cd "EduMesh-Android"
flutter build apk --release --target-platform android-arm,android-arm64
scp build/app/outputs/flutter-apk/app-release.apk user@server:Project-Lumina/uploads/EduMesh.apk
sudo systemctl restart lumina-hub.service
```

### Quality gates

```bash
dart analyze lib/                    # Must be 0 errors, 0 warnings
flutter test                         # Smoke test
flutter gen-l10n                     # Regenerate localizations after ARB changes
cd "Debian Server" && pytest         # 38 tests
```

---

## Roadmap

| Area | Status |
|---|---|
| Student app core (browse, download, view, offline) | Shipped |
| Courses, quizzes, flashcards (SM-2) | Shipped |
| Teacher/admin web dashboard, 6-language i18n | Shipped |
| ZIM/Kiwix offline article browsing | Shipped |
| Phone-to-phone sharing (ShareServer) | Shipped |
| Hub-to-hub federation | Removed (2026-08); not planned to return |
| 250-student concurrency load test | Open (design target, untested at scale) |
| Grade-level expansion (pre-primary to Grade 13) | Open |
| `task_queue.py` + `thumb_worker.py` background workers | Planned |
| `encryption.py` (`EncryptedAPIRoute` for sensitive aggregates) | Planned |
| Sustained multi-week field deployment | Open |

The authoritative shipped/cut/open tracker is [`feature-roadmap.md`](Markdown%20files/feature-roadmap.md).

---

## Documentation

- [`AGENTS.md`](AGENTS.md): engineering contract, covering architecture, performance rules, accessibility, i18n rules, security, offline-first requirements, and commit conventions.
- [`DESIGN.md`](Markdown%20files/DESIGN.md): source of truth for colour tokens, typography, spacing grid.
- [`implementation-details.md`](Markdown%20files/implementation-details.md): deep dives on `.part` atomicity, connectivity heartbeat, black-skip thumbnails, three-tier token renewal.
- [`docs/`](docs/): ADRs, API sync verification, ZIM search redesign, operator guide, i18n debt tracker.
- [`LMS Docs/`](LMS%20Docs/): course/quiz system design, implementation plan, and edge cases.

---

## Contributing and Credits

College project submission. Rishi Raj set the architecture and technical direction, and wrote the FastAPI server, the full web dashboard, and the deployment tooling. Felice George wrote the Flutter mobile dashboard and led UI/UX and accessibility work. The offline-first data layer (catalog cache, mutation/download queues, connectivity) is joint work with Rishi Raj as primary author.

Before touching code, read [`AGENTS.md`](AGENTS.md) in full. It defines the conventions that make the two parallel projects (Flutter app + FastAPI server) safe to work on simultaneously: the commit message convention (Conventional Commits), the parallel-subagent execution rule, and the audit gates PRs must pass (`dart analyze lib/` at 0 errors/0 warnings, pytest green, ARB/JSON key parity across all 6 languages).

---

## License

MIT