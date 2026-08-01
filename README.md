<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi" alt="FastAPI">
  <img src="https://img.shields.io/badge/SQLite-WAL-003B57?logo=sqlite" alt="SQLite WAL">
  <img src="https://img.shields.io/badge/Offline--First-✓-brightgreen" alt="Offline-First">
  <img src="https://img.shields.io/badge/WCAG_AA-✓-brightgreen" alt="WCAG AA">
  <img src="https://img.shields.io/badge/i18n-4_Languages-important" alt="i18n">
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
- [Lessons Learned](#lessons-learned)
- [Performance Targets and Reality](#performance-targets-and-reality)
- [Hard Trade-offs](#hard-trade-offs)
- [Tech Stack](#tech-stack)
- [Setup and Deployment](#setup-and-deployment)
- [Future Roadmap](#future-roadmap)
- [Implementation Details](#implementation-details)
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
│  └─────────────────────┘  │                                       │  │ session prune   │  │
│                           │                                       │  └─────────────────┘  │
└───────────────────────────┘                                       └───────────────────────┘
```

Two independent codebases, plain HTTP between them.

---

## Features

### EduMesh Android App (Flutter)

A Flutter 3 app (52 Dart files, 41 dependencies) built for sub-$50 phones (1 to 2 GB RAM, MediaTek MT6739). The whole app works around one constraint: the hub might disappear at any moment.

**Offline infrastructure**

- **Catalog cache:** `CatalogService` stores the full resource list in local SQLite. You can browse, search, and filter without the hub. The app replaces the entire cache inside a single transaction, so a mid-sync dropout never leaves you with partial data.
- **Download queue:** `DownloadQueue` processes one file at a time with exponential backoff (3s, 6s, 12s, 24s, 48s). Files download to a `.part` name and rename on completion. A partial download never shows up as a finished file.
- **Mutation queue:** `MutationQueue` persists profile updates and activity events when the hub is unreachable. On reconnect, it replays them in order. After 3 retries it logs the failure and moves on.
- **Connectivity monitor:** Hybrid detection using `connectivity_plus` for instant platform events and a 30-second HTTP `/ping` heartbeat (4-second timeout). On reconnect, it flushes pending downloads, mutations, and catalog cache.

**Content experience**

- **Course browser and player:** Browse, enroll, and track progress through structured courses. Courses contain resources organized by topics with teacher-authored quizzes.
- **Video with picture-in-picture:** `MiniPlayerController` is a singleton. Navigate back from full-screen and playback continues in a mini overlay. Closing the overlay disposes both `VideoPlayerController` and `ChewieController`.
- **PDF viewer:** `pdfx` with pinch-to-zoom (0.5x to 5.0x). Page position saved to `SharedPreferences`. A 6-column page grid for rapid navigation.
- **ZIM article browser:** Fetches up to 500 articles (capped to prevent OOM on 1 GB phones). Displays them as searchable items with a WIKI badge.
- **Search recommendations:** Every resource gets a score: +3 for matching grade, +2 for matching a previously accessed subject, +1 for matching the most-viewed resource type. The top 6 appear as "Recommended for You".

**Resilience**

- **Triple data fallback:** Every resource lookup tries server API, `CatalogService` SQLite cache, then `DBHelper` downloads table. Undownloaded resources appear as ghost items at 50% opacity when offline.
- **Staleness detection:** Before opening a local file, the app compares cached mtime against the server. If outdated, it re-downloads automatically.
- **Token renewal:** 3-tier fallback (session token, 7-day refresh token, 365-day persistent key). The interceptor tries each on 401/403 before logging out.
- **Server discovery:** DNS `lumina.hub` (3s timeout), fallback `10.42.0.1:8000`, then persisted fallback IP from `SharedPreferences`.

**UX and accessibility**

- **4 languages:** English, Hindi, Kannada, French. 338 translatable strings with ICU plurals (Flutter), 703 keys (web). All fonts are bundled as `.ttf`. `GoogleFonts` is fallback only.
- **Touch targets:** Every tappable element meets 48x48px minimum. `Semantics` labels on all controls. `Tooltip` on icon-only buttons.
- **Double-back-to-exit:** `PopScope` with a 2-second window. First back press shows a SnackBar with an Exit button. Second press calls `SystemNavigator.pop()`.
- **4-tab navigation:** Dashboard, Browse, Saved, Profile. All tabs always visible regardless of role.

### Lumina Hub Server (FastAPI)

A FastAPI app (30 Python files, SQLite WAL) running on 2 to 8 GB RAM with a 5400 RPM HDD. It serves content, collects analytics, hosts a web dashboard, and exposes 100+ API endpoints.

The API is split across 20 router modules plus `zim_handler.py`. Together they cover auth, student sync, teacher analytics, course management, content CRUD, media streaming, account management, passwords, audit logs, system health, and ZIM serving.

| Router | Lines | Purpose |
|---|---|---|
| `auth.py` | 293 | Login, register, token management |
| `student.py` | 308 | Sync, analytics, profile, icons |
| `student_courses.py` | 499 | Course browsing, enrollment, progress, quizzes |
| `teacher_courses.py` | 237 | Course CRUD, publish toggle, similar suggestions |
| `teacher_students.py` | 253 | Student listing, teacher analytics |
| `teacher_course_resources.py` | 416 | Course resource upload, ZIP import/export |
| `teacher_topics.py` | 141 | Course topic CRUD, ordering |
| `teacher_quizzes.py` | 114 | Quiz creation and editing |
| `teacher_similar.py` | 77 | Similar course links |
| `academics.py` | 415 | Subjects, grades, resource topics CRUD |
| `resources.py` | 332 | Resource CRUD, upload, catalog |
| `resource_zim.py` | 261 | ZIM upload, processing, deletion |
| `media.py` | 167 | HTTP Range streaming, thumbnails |
| `administration.py` | 203 | Account management |
| `passwords.py` | 114 | Password change, reset |
| `admin_logs.py` | 140 | Audit log, settings, log download |
| `system_stats.py` | 143 | Hub stats, health, time sync |
| `system.py` | 164 | Health check, captive portal, static serving |
| `scholars.py` | 84 | Scholar listing, reset, delete |

Background services run as `asyncio` tasks inside the server process:

- **zim_auto_cleaner.py** -- Hourly LRU-based pruning of ZIM cache. Configurable via a JSON config file with thread-safe access.
- **Session pruning** -- Stale session cleanup runs periodically.

Additional services (task queue, thumbnail worker, mDNS discovery, rate limiting middleware, encrypted API routes) are planned but not yet created.

### Web Dashboard

A teacher/admin dashboard served from the hub (9 HTML pages, vanilla JS). Role-based access: students see the captive portal, teachers see the dashboard, admins see everything including danger-zone controls.

Features: resource management, student analytics, course creation, grade/subject management, audit logs, system settings, and password management. Fully translated to 4 languages.

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

---

## Hard Trade-offs

**SQLite over PostgreSQL.** WAL mode handles 30 concurrent writes on a Celeron with 2 GB RAM, and it's zero-config for teachers who aren't DBAs. But I lose true multi-writer concurrency. If a school scales beyond 100 students, I'll need to migrate.

**500-article ZIM limit.** ZIM archives can hold hundreds of thousands of articles. Loading them all would OOM a 1 GB phone. The 500-article cap guarantees the app never crashes on search. The downside: deep research across large archives needs multiple queries.

**Smoke tests only.** I spent my limited time on offline reliability (mutation queue, download atomicity, Keystore recovery) instead of test coverage. That was the right call for v1. But now refactoring is riskier without an integration test suite. A pytest suite with 6 async tests covers the core API paths.

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
| **Frontend** | Vanilla HTML/CSS/JS | Teacher/admin dashboard (9 pages) |
| **i18n (Flutter)** | ARB files + `flutter gen-l10n` | 4 languages, ICU plurals, 338 keys |
| **i18n (Web)** | JSON lang files + `lumina.js` | 4 languages, 703 keys each |

---

## Setup and Deployment

### Production Deployment (on Debian laptop)

```bash
git clone <repo> /opt/lumina
cd /opt/lumina/"Debian Server"
sudo ./setup_hub.sh          # Idempotent. Run once.
sudo systemctl start lumina-hub
```

The script provisions system dependencies, Python venv, UFW firewall, dnsmasq captive portal DNS, systemd services, lid-close sleep disable, nightly reboot, and unlimited file descriptors.

### Commands

```bash
# Flutter app
dart analyze lib/                     # Lint Flutter code
flutter test                          # Run Flutter smoke test
flutter gen-l10n                      # Regenerate localizations after ARB changes
flutter build apk --release           # Build release APK

# Server
python main.py                        # Start server (dev)
sudo systemctl restart lumina-hub     # Start server (prod)
cd "Debian Server" && pytest          # Run API tests
```

---

## Future Roadmap

| Area | Direction |
|---|---|
| **Peer-to-peer sync** | Multi-hub federation for village clusters |
| **Grade-level expansion** | Pre-primary (Grade 0) to competitive exam prep (Grade 13) |
| **Richer offline states** | `ConnectionGate` shows a red banner today; extend to serve full cached-content fallback views |
| **Background workers** | Task queue for thumbnail generation, ZIM processing, and long-running imports |

---

## Implementation Details

For deep dives into specific design decisions (.part file atomicity, connectivity heartbeat, black-skip thumbnails, 3-tier token renewal, and more), see [Implementation Details](Markdown files/implementation-details.md).

For the LMS course/quiz system design, see [LMS Implementation Plan](LMS%20Docs/LMS_Implementation_Plan.md) and [LMS Edge Cases](LMS%20Docs/LMS_Edge_Cases_Deep_Dive.md).

---

## Contributing

College-project submission by:

- **Rishi Raj** ([RajKnight1896](https://github.com/RajKnight1896)) -- architecture, server, API, web dashboard, deployment
- **Felice George** ([Felice18](https://github.com/Felice18)) -- Flutter mobile dashboard, UI/UX, accessibility

---

## License

MIT
