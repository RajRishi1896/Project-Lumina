<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi" alt="FastAPI">
  <img src="https://img.shields.io/badge/SQLite-WAL-003B57?logo=sqlite" alt="SQLite WAL">
  <img src="https://img.shields.io/badge/Offline--First-✓-brightgreen" alt="Offline-First">
  <img src="https://img.shields.io/badge/WCAG_AA-✓-brightgreen" alt="WCAG AA">
  <img src="https://img.shields.io/badge/i18n-6_Languages-important" alt="i18n">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

# Project Lumina · EduMesh Hub

An offline-first educational mesh for rural schools. One repurposed laptop acts as a WiFi hotspot and content server. Students access textbooks, videos, and interactive content on their phones. No internet required.

---

## Quick Start

```bash
# Terminal 1: start the hub server
cd "Debian Server" && python main.py

# Terminal 2: launch the student app
cd "EduMesh-Android" && flutter run
```

The server runs on `http://0.0.0.0:8000`. The app connects via DNS `lumina.hub` (3s timeout), falling back to `10.42.0.1:8000` if DNS resolution fails. Default admin login: `admin` / `lumina2026`.

---

## Contents

- [Why I Built This](#why-i-built-this)
- [Who This Is For](#who-this-is-for)
- [Hardest Technical Challenges](#hardest-technical-challenges)
- [Architecture](#architecture)
- [Features](#features)
- [API Overview](#api-overview)
- [Database Schema](#database-schema)
- [Localization](#localization)
- [Lessons Learned](#lessons-learned)
- [Performance Targets and Reality](#performance-targets-and-reality)
- [Hard Trade-offs](#hard-trade-offs)
- [Tech Stack](#tech-stack)
- [Setup and Deployment](#setup-and-deployment)
- [Future Roadmap](#future-roadmap)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Why I Built This

I visited a government school in a village where 40 students shared three smartphones. The school had one desktop running Windows 7 and a data dongle that worked maybe two hours a day. Teachers carried lesson plans on USB drives. Kids who wanted to study at home had nothing.

Existing LMS platforms assume every student has a device, always-on broadband, and a stable power grid. That's not the reality I saw. So I built the opposite: a system that assumes nothing. No internet. One laptop for an entire school. Content that arrives on a USB stick. Progress that syncs in the 30 seconds a phone is near the hub.

I called it Project Lumina. It's an offline-first educational mesh for places where the cloud is the exception, not the rule.

## Who This Is For

- **Rural schools** where one repurposed laptop serves a whole class. The laptop runs the hub server, the WiFi hotspot, and the captive portal.
- **Students sharing devices** who need profile switching, offline browsing, and progress that doesn't disappear when the WiFi drops.
- **Teachers in low-infrastructure regions** who upload PDFs and videos once and assign them without worrying about connectivity.
- **NGOs and community centers** deploying offline learning kits in villages without power-grid reliability.

## Hardest Technical Challenges

**SQLite under 30 concurrent syncs.** The hub runs on 2 GB RAM with a 5400 RPM HDD. Thirty students syncing study time and downloads every 60 seconds would overwhelm a naive database. I switched to WAL mode, throttled `last_accessed` writes to a 5-minute staleness window (dropped write frequency by roughly 99.7%), and offloaded CPU-heavy work to background async tasks with timeout controls.

**Video thumbnails that skip black title cards.** Many educational videos start with a 5 to 15 second black screen. Taking a thumbnail at a fixed timestamp produces a black image. I used ffmpeg's `blackdetect` filter to find the first non-black frame, added one second, and capped at 30 seconds to avoid picking an ending frame. This runs in a background worker so it never blocks a request.

**Android Keystore crashes on lock screen removal.** `FlutterSecureStorage` is tied to the Android Keystore. When a student removes their lock screen PIN, the Keystore invalidates every stored key. Every subsequent `read()` throws a `PlatformException` and the app crash-loops. I catch this at the read site, call `deleteAll()` to clear corrupted state, and let the next login rebuild from scratch. Without this guard, the app is bricked until reinstalled.

**Two independent auth systems, one password field.** Offline login uses SHA-256 (fast, local-only). Online login uses bcrypt (slow, server-side). They share the same credential entry point but never the same hash. A breach of one system doesn't compromise the other. Getting this split right without confusing users took several iterations.

---

## Architecture

```
┌───────────────────────────┐       WiFi Hotspot (10.42.0.1)        ┌───────────────────────┐
│                           │ ◄─────── HTTP / DNS ────────────────► │                       │ 
│   EduMesh Android App     │                                       │   Lumina Hub Server   │
│   (Flutter 3.x)           │                                       │   (FastAPI + SQLite)  │
│                           │                                       │                       │
│  ┌─────────────────────┐  │   GET /api/catalog                    │ ┌──────────────────┐  │
│  │ CatalogService      │──┼──────────────────────────────────────►│ │ uploads/         │  │
│  │ (SQLite cache)      │◄─┼────────────────────────────────────── │ │ (PDFs, videos)   |  │
│  └─────────────────────┘  │                                       │ └──────────────────┘  │
│                           │   POST /student/sync-study-time       │  ┌─────────────────┐  │
│  ┌─────────────────────┐  │──────────────────────────────────────►│  │ thumbnails/     │  │
│  │ ActivityTracker     │  │                                       │  │ (ffmpeg/PyMuPDF)│  │
│  │ (debounced, 60s)    │  │                                       │  └─────────────────┘  │
│  └─────────────────────┘  │   GET /api/stream/{file} (Range)      │  ┌─────────────────┐  │
│                           │◄──────────────────────────────────────│  │ zim_pages/      │  │
│  ┌─────────────────────┐  │                                       │  │ (Kiwix articles)│  │
│  │ DownloadQueue       │  │                                       │  └─────────────────┘  │
│  │ (sequential, retry) │  │   POST /student/sync-downloads        │                       │
│  └─────────────────────┘  │──────────────────────────────────────►│  ┌─────────────────┐  │
│                           │                                       │  │ data/hub.db     │  │
│  ┌─────────────────────┐  │   POST /student/sync-subject-time     │  │ (SQLite WAL)    │  │
│  │ MutationQueue       │──┼──────────────────────────────────────►│  └─────────────────┘  │
│  │ (offline queue)     │  │                                       │                       │
│  └─────────────────────┘  │                                       │  ┌─────────────────┐  │
│                           │                                       │  │ Web Dashboard   │  │
│  ┌─────────────────────┐  │                                       │  │ (manage-*.html) │  │
│  │ MiniPlayer          │  │                                       │  │ i18n, role-based│  │
│  │ (PiP overlay)       │  │                                       │  └─────────────────┘  │
│  └─────────────────────┘  │                                       │                       │
│                           │                                       │  ┌─────────────────┐  │
│  ┌─────────────────────┐  │                                       │  │ Background tasks│  │
│  │ 4-tab Shell         │  │                                       │  │ thumbnail gen   │  │
│  │ (double-back exit)  │  │                                       │  │ ZIM auto-clean  │  │
│  └─────────────────────┘  │                                       │  │ peer refresh    │  │
│                           │                                       │  └─────────────────┘  │
└───────────────────────────┘                                       └───────────────────────┘
```

Two independent codebases, plain HTTP between them. The two projects share no code, no dependencies, and no toolchain — see [`AGENTS.md`](AGENTS.md) for the parallel-work conventions that govern both.

---

## Features

### EduMesh Android App (Flutter)

A Flutter 3 app (65 Dart files, 23 dependencies) built for sub-$50 phones (1 to 2 GB RAM, MediaTek MT6739). The whole app works around one constraint: the hub might disappear at any moment.

**Offline infrastructure**

- **Catalog cache:** `CatalogService` stores the full resource list in local SQLite. You can browse, search, and filter without the hub. The app replaces the entire cache inside a single transaction, so a mid-sync dropout never leaves you with partial data.
- **Download queue:** `DownloadQueue` processes one file at a time with exponential backoff (3s, 6s, 12s, 24s, 48s). Files download to a `.part` name and rename on completion. A partial download never shows up as a finished file.
- **Mutation queue:** `MutationQueue` persists profile updates and activity events when the hub is unreachable. On reconnect, it replays them in order. After 3 retries it logs the failure and moves on.
- **Connectivity monitor:** Hybrid detection using `connectivity_plus` for instant platform events and a 30-second HTTP `/ping` heartbeat (4-second timeout). On reconnect, it flushes pending downloads, mutations, and catalog cache.

**Content experience**

- **Course browser and player:** Browse, enroll, and track progress through structured courses. Courses contain resources organized by topics with teacher-authored quizzes.
- **Flashcards:** Full SM-2 spaced-repetition decks. Students review decks in the app; teachers create decks and review submissions on the web dashboard.
- **Video with picture-in-picture:** `MiniPlayerController` is a singleton. Navigate back from full-screen and playback continues in a mini overlay. Closing the overlay disposes both `VideoPlayerController` and `ChewieController`.
- **PDF viewer:** `pdfx` with pinch-to-zoom (0.5x to 5.0x). Page position saved to `SharedPreferences`. A 6-column page grid for rapid navigation.
- **ZIM article browser:** Fetches up to 500 articles (capped to prevent OOM on 1 GB phones). Displays them as searchable items with a WIKI badge. Downloaded articles have all assets inlined as data URIs for full offline rendering.
- **Search recommendations:** Every resource gets a score: +3 for matching grade, +2 for matching a previously accessed subject, +1 for matching the most-viewed resource type. The top 6 appear as "Recommended for You".

**Resilience**

- **Triple data fallback:** Every resource lookup tries server API, `CatalogService` SQLite cache, then `DBHelper` downloads table. Undownloaded resources appear as ghost items at 50% opacity when offline.
- **Staleness detection:** Before opening a local file, the app compares cached mtime against the server. If outdated, it re-downloads automatically.
- **Token renewal:** 3-tier fallback (session token, 7-day refresh token, 365-day persistent key). The interceptor tries each on 401/403 before logging out.
- **Server discovery:** DNS `lumina.hub` (3s timeout), fallback `10.42.0.1:8000`, then persisted fallback IP from `SharedPreferences`.

**UX and accessibility**

- **6 languages:** English, Hindi, Kannada, French, Tamil, Telugu. 402 translatable strings with ICU plurals (Flutter), 754 keys (web). All fonts are bundled as `.ttf`. `GoogleFonts` is fallback only.
- **Touch targets:** Every tappable element meets 48x48px minimum. `Semantics` labels on all controls. `Tooltip` on icon-only buttons.
- **Double-back-to-exit:** `PopScope` with a 2-second window. First back press shows a SnackBar with an Exit button. Second press calls `SystemNavigator.pop()`.
- **4-tab navigation:** Dashboard, Browse, Saved, Profile. All tabs always visible regardless of role.

### Lumina Hub Server (FastAPI)

A FastAPI app (SQLite WAL) running on 2 to 8 GB RAM with a 5400 RPM HDD. It serves content, collects analytics, hosts a web dashboard, and exposes 188 routes across 24 router modules plus `zim_handler.py`.

The routers cover auth, student sync, teacher analytics, course management, content CRUD, media streaming, account management, passwords, audit logs, system health, ZIM serving, and peer-hub federation.

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
| `resource_catalog.py` | 228 | Read-only catalog/detail/files/limits + shared cache |
| `resource_zim.py` | 493 | ZIM upload, processing, deletion |
| `peer_zim_proxy.py` | 53 | Signed peer ZIM search receive (mesh) |
| `media.py` | 336 | HTTP Range streaming, thumbnails |
| `administration.py` | 206 | Account management |
| `passwords.py` | 109 | Password change, reset |
| `admin_logs.py` | 220 | Audit log, settings, log download |
| `system_stats.py` | 572 | Hub stats, health, time sync |
| `system.py` | 188 | Health check, captive portal, static serving |
| `scholars.py` | 99 | Scholar listing, reset, delete |
| `federation.py` | 395 | Peer hub pairing, catalog, file proxying |

Background services run as `asyncio` tasks inside the server process:

- **`discovery.py`** -- mDNS/DNS-SD beacon (zeroconf) so phones can find the hub by name.
- **`peer_refresh.py`** -- hourly catalog sync from paired peer hubs (pull-only, no student data crosses).
- **`zim_auto_cleaner.py`** -- hourly LRU-based pruning of ZIM cache. Configurable via a JSON config file.
- **`maintenance.py`** -- recycled-resource purge, session pruning.
- **`metrics.py`** -- hub health / stats reporting.
- **Rate limiting** -- `middleware.py`, per-IP token bucket (200 req/min default). Exempt: localhost, `/static/*`, `/files/*`, `/ping`, `/generate_204`, and GET `/zim/*`. `/peer/pair` is capped at 10/300 and ZIM uploads at 5/300.

Still planned (see [Future Roadmap](#future-roadmap)): `task_queue.py` (background worker pool), `thumb_worker.py` (off-request thumbnail generation), `encryption.py` (`EncryptedAPIRoute` for sensitive aggregates).

### Web Dashboard

A teacher/admin dashboard served from the hub (11 HTML pages, vanilla JS). Role-based access: students see the captive portal, teachers see the dashboard, admins see everything including danger-zone controls.

Pages: dashboard, courses, students, student detail, content manager, flashcards, danger zone, settings, help, welcome (captive portal), error. Features: resource management, student analytics, course creation, grade/subject management, flashcards, audit logs, system settings, and password management. Fully translated to 6 languages.

---

## API Overview

188 routes grouped by prefix. All student- and teacher-facing routes are under `/api`, `/student`, `/teacher`; peer-hub federation is under `/peer`; captive-portal and health routes are public.

| Prefix | Routes | What they do |
|---|---|---|
| `/api/*` | 79 | Catalog, resources, ZIM articles, uploads, streaming |
| `/teacher/*` | 31 | Course CRUD, topics, quizzes, resources, students, flashcards, similar |
| `/student/*` | 21 | Sync (study time, downloads, subjects), analytics, profile, icons |
| `/peer/*` | 10 | Federation: hello, pair (6-digit + Ed25519), catalog, file proxy |
| `/zim/*` | 6 | ZIM page/asset/thumbnail serving, article search |
| `/system/*` | 6 | Health, ping, captive portal, whoami, static serving |
| `/grades` | 4 | Grade taxonomy CRUD |
| `/resources`, `/sync`, `/logout` | 6 | Resource detail, student sync, session logout |
| `/docs`, `/redoc`, `/openapi.json` | 4 | FastAPI interactive docs |
| `/`, `/welcome`, `/dashboard`, `/index.html`, captive-portal probes | 10 | Web pages + OS captive-portal detection URLs |

Key endpoint behaviours:

- **Streaming:** video files are served through `/api/stream/` with HTTP Range support (206 Partial Content) so students can seek without full download.
- **Soft delete:** deleting a resource sets `status = 'deleted'` + `deleted_at` (30-day recycle bin); the hourly purge hard-deletes file + row. Deleted resources are excluded from catalog/search but reachable by direct ID.
- **Peer resources:** `/api/catalog` merges approved peer-hub resources as `peer:{peer_id}:{resource_id}` with `pdf_url` proxied through `/peer/file/{peer_id}/{resource_id}`.
- **Auth:** JWT-style session tokens with 3-tier renewal; students are force-password-reset on first registration. Full OpenAPI spec at `/docs` when the server is running.

---

## Database Schema

Single SQLite file at `data/hub.db` in WAL mode. All access goes through `app/async_db.py` helpers which run queries in a thread pool (`asyncio.to_thread`) so the event loop stays free. The Flutter app mirrors the catalog/progress tables in its own local SQLite (v17 schema).

**Accounts & auth**

| Table | Purpose |
|---|---|
| `users` | Teacher/admin accounts (username, bcrypt hash, role) |
| `scholars` | Student accounts (id, name, grade, username) |
| `sessions` / `refresh_tokens` / `persistent_keys` | 3-tier token tables |
| `settings` | Key/value hub settings |

**Content**

| Table | Purpose |
|---|---|
| `resources` | Uploaded files (title, subject, grade, language, type, source, license, status) |
| `subjects`, `grades` | Taxonomy (subjects/grades used across resources and courses) |
| `resource_topics` | Topic tags for standalone resources |
| `zim_archives` / `zim_articles` | ZIM archive + per-article metadata |
| `peers`, `peer_resources` | Paired hub identities + mirrored catalog entries |

**Courses & quizzes**

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
| `activity_logs` | Per-student event log (references student id, never names) |
| `student_bookmarks` | Student-saved resources |

---

## Localization

6 languages: **English, Hindi, Kannada, French, Tamil, Telugu.** Source languages are `app_en.arb` (Flutter) and `static/lang/en.json` (web); all other languages must keep identical key sets.

| Platform | Count | Key syntax | Location |
|---|---|---|---|
| Flutter | 402 keys × 6 files | `lowerCamelCase`, ICU plurals | `lib/l10n/app_*.arb` |
| Web | 754 keys × 6 files | `lower_snake_case`, dot-namespaced | `static/lang/*.json` |

Rules (full spec in `AGENTS.md` → Localization):

- **No hardcoded user-facing text** in Flutter widgets or web HTML/JS. Dialogs, snackbars, errors, titles, tooltips, empty states all must localize.
- **English ships with every feature** — new keys go in `app_en.arb` + `en.json` in the same PR as the feature.
- **English is the runtime fallback** for any missing key in a target language.
- **Glossary is the source of truth** for educational terms (Student/Teacher/Chapter/Download/Offline/... — see AGENTS.md table).
- **Simple language** for students: 12–15 words per sentence, active voice, everyday words. No error codes as primary messages.
- **Fonts are bundled offline** as `.ttf` (Noto Sans per script) — `GoogleFonts` is fallback only.
- **Plain language rules:** errors must say *what happened, why, what to do next*; buttons are verbs ("Download", "Open", "Try Again"); no urban-only analogies.

---

## Lessons Learned

Offline-first is not a feature toggle. It's a complete rethinking of state management, error handling, and UX. Every API call needs a local fallback. Every write must survive a sudden disconnection. Every screen must render without the server.

Designing for constraints taught me more about distributed systems than building for abundance ever could. The hardest problems weren't the algorithms. They were the edge cases: a phone going to sleep mid-download, a Keystore corrupting on lock screen removal, a file rename failing on FAT32.

---

## Performance Targets and Reality

Measured on actual target hardware: MediaTek MT6739, 1 GB RAM, Android 8 (phone); Intel Celeron N4020, 4 GB RAM, 5400 RPM HDD (server).

| Metric | Target | Actual |
|---|---|---|
| Cold start to interactive | <= 4 s | **3.2 s** |
| Dashboard catalog load (cached) | <= 800 ms | **450 ms** |
| Resource list scroll (60 fps) | 0 jank frames | **0 jank** |
| SQLite query (single resource) | <= 50 ms | **12 ms** |
| APK size (release) | <= 25 MB | **18 MB** |
| First video frame (streaming) | - | **1.1 s** |

**Server under 50 concurrent students (syncing every 60 seconds):**

| Metric | Result |
|---|---|
| Average response time | < **200 ms** |
| Catalog listing (200 resources) | **45 ms** |
| PDF thumbnail generation (10 MB file) | **350 ms** (background) |
| Video thumbnail generation (1080p, 15 min) | **4.2 s** (background) |

The concurrency target is **250 concurrent students** without degraded response times. Any regression of more than 20% on the table above requires justification and a mitigation plan.

---

## Hard Trade-offs

**SQLite over PostgreSQL.** WAL mode handles 30 concurrent writes on a Celeron with 2 GB RAM, and it's zero-config for teachers who aren't DBAs. But I lose true multi-writer concurrency. If a school scales beyond 100 students, I'll need to migrate. The DB layer is isolated behind `async_db.py`, which is the seam for that migration.

**500-article ZIM limit.** ZIM archives can hold hundreds of thousands of articles. Loading them all would OOM a 1 GB phone. The 500-article cap guarantees the app never crashes on search. The downside: deep research across large archives needs multiple queries.

**Test coverage vs offline reliability.** I spent my limited time on offline reliability (mutation queue, download atomicity, Keystore recovery) instead of test coverage. That was the right call for v1. The pytest suite now covers 52 tests across 6 files (API, federation/HMAC signing, flashcards, quiz integrity, resource security) — enough to make refactoring safe, still not exhaustive.

**.part file convention on FAT32.** The rename isn't truly atomic on FAT32 or exFAT, which is what most cheap SD cards use. But the .part convention still prevents corrupted files from masquerading as complete. A crash during rename leaves at most one orphaned file. The alternative (write to a temp dir, then move) has the same fundamental limitation on these filesystems.

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Mobile app** | Flutter 3.x (Dart) | Cross-platform Android student client |
| **HTTP client** | Dio 5 (`dio`) | API calls, interceptors, retry |
| **Local database** | SQLite via `sqflite` | Offline cache, pending queues |
| **Secure storage** | `flutter_secure_storage` | Session tokens, credentials |
| **Server** | FastAPI (Python) | REST API, background tasks, static files |
| **DB** | SQLite WAL mode | Analytics, sessions, content metadata |
| **Auth (server)** | bcrypt + JWT-style session tokens | Password hashing, role-based access |
| **Auth (offline client)** | SHA-256 (local-only) | Offline credential verification |
| **Thumbnails** | ffmpeg + PyMuPDF | Video black-intro skip, PDF 0.3x scale |
| **Video streaming** | HTTP Range requests | 206 Partial Content for seek |
| **Captive portal** | dnsmasq + NetworkManager | DNS hijack to hub welcome page |
| **Federation** | zeroconf (mDNS) + cryptography (Ed25519) | Peer discovery + signed pairing |
| **Frontend** | Vanilla HTML/CSS/JS | Teacher/admin dashboard (11 pages) |
| **i18n (Flutter)** | ARB files + `flutter gen-l10n` | 6 languages, ICU plurals, 402 keys |
| **i18n (Web)** | JSON lang files + `lumina.js` | 6 languages, 754 keys each |

---

## Setup and Deployment

### Production Deployment (on Debian laptop)

```bash
git clone <repo> /opt/lumina
cd /opt/lumina/"Debian Server"
sudo ./setup_hub.sh          # Idempotent. Run once.
sudo systemctl start lumina-hub
```

The script provisions system dependencies, Python venv, UFW firewall, dnsmasq captive portal DNS, systemd services, lid-close sleep disable, nightly reboot, and unlimited file descriptors. It completes without internet after the initial package-install pass.

### Commands

```bash
# Flutter app
dart analyze lib/                     # Lint Flutter code (must be 0 errors / 0 warnings)
flutter test                          # Run Flutter smoke test
flutter gen-l10n                      # Regenerate localizations after ARB changes
flutter build apk --release           # Build release APK (target ~18 MB)

# Server
python main.py                        # Start server (dev)
sudo systemctl restart lumina-hub     # Start server (prod)
cd "Debian Server" && pytest          # Run API tests (52 tests)
```

---

## Future Roadmap

| Area | Direction |
|---|---|
| **Peer-to-peer sync** | Multi-hub federation for village clusters (pairing + catalog + file proxy shipped; deeper sync open) |
| **Grade-level expansion** | Pre-primary (Grade 0) to competitive exam prep (Grade 13) |
| **Richer offline states** | `ConnectionGate` shows a red banner today; extend to serve full cached-content fallback views |
| **Background workers** | `task_queue.py` + `thumb_worker.py` -- move thumbnail/ZIM work off request handlers |
| **Encrypted API route** | `encryption.py` -- AES-GCM `EncryptedAPIRoute` for student-list and analytics aggregates |

The authoritative status of shipped vs cut vs open items is [`feature-roadmap.md`](Markdown%20files/feature-roadmap.md).

---

## Documentation

- **[`AGENTS.md`](AGENTS.md)** -- the engineering contract: architecture, performance rules, accessibility standards, i18n rules, security, offline-first requirements, commit conventions.
- **[`DESIGN.md`](Markdown%20files/DESIGN.md)** -- source of truth for colour tokens, typography, spacing grid.
- **[`implementation-details.md`](Markdown%20files/implementation-details.md)** -- deep dives on .part file atomicity, connectivity heartbeat, black-skip thumbnails, 3-tier token renewal.
- **[`docs/`](docs/)** -- ADRs, API sync verification, ZIM search redesign, operator guide, i18n debt tracker.
- **[`LMS Docs/`](LMS%20Docs/)** -- LMS course/quiz system design: [implementation plan](LMS%20Docs/LMS_Implementation_Plan.md) and [edge cases](LMS%20Docs/LMS_Edge_Cases_Deep_Dive.md).

---

## Contributing

College-project submission by:

- **Rishi Raj** ([RajKnight1896](https://github.com/RajKnight1896)) -- architecture, server, API, web dashboard, deployment
- **Felice George** ([Felice18](https://github.com/Felice18)) -- Flutter mobile dashboard, UI/UX, accessibility

Before touching code, read [`AGENTS.md`](AGENTS.md) in full -- it defines the rules that make the two parallel projects (Flutter app + FastAPI server) safe to work on simultaneously, the commit message convention (Conventional Commits), and the audit gates that PRs must pass (`dart analyze lib/` at 0 errors/0 warnings, pytest green, ARB/JSON key parity across all 6 languages).

---

## License

MIT
