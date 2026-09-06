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

A repurposed laptop runs a WiFi hotspot, a FastAPI content server, and a captive portal. Students reach textbooks, videos, and interactive content from Android phones over the local network. No internet connection exists in the loop.

## Table of Contents

- [Overview](#overview)
- [Who It Is For](#who-it-is-for)
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

Project Lumina is a proof of concept: an offline-first learning platform for schools where broadband, stable power, and student-owned devices cannot be assumed. One low-cost server laptop hosts all content and services. Android phones on a local hotspot consume the content through a Flutter app that remains fully usable when the hub is unreachable. The PoC is complete and shipped.

Two independent codebases form the system: a Flutter Android client (`EduMesh-Android/`, 66 Dart files) and a FastAPI server (`Debian Server/`, 22 router modules plus a ZIM handler). They share no code, no dependencies, and no toolchain. They communicate over plain HTTP on the local network, with the laptop acting as gateway at the static address `10.42.0.1`.

**Why it exists.** Existing LMS platforms assume always-on broadband and one device per student. The environment this target provides neither. The project instead assumes nothing: no internet, one laptop for an entire school, content delivered by USB stick, and progress synchronized in the brief window a phone is near the hub. The PoC proved the architecture works; it is not a product roadmap.

**Current maturity.** This is a proof of concept that shipped. The system is feature-complete for single-classroom and school-lab deployment. It passes a 64-test pytest suite and a 56-test Flutter suite, `dart analyze` at 0 errors and 0 warnings, and has run end-to-end on emulators and development hardware. The 250-concurrent-student concurrency target is a design figure validated only at small scale; a repeatable benchmark harness is not in scope. What exists works. What doesn't exist was never needed for the PoC.

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
- **Profile isolation.** Each profile gets its own SQLite file (`lumina_{userId}.db`). Switching profiles closes the old DB handle and opens the new one. No cross-profile data leakage.
- **Offline quiz grading.** Server sends answer keys with quiz data for offline grading. Quiz attempts persist locally and sync to server on reconnect. Timer pauses on app background instead of auto-submitting.

**Content experience**

- **Course browser and player.** Browse, enroll, and track progress through structured courses. Courses contain resources organized into ordered topics with teacher-authored quizzes.
- **Flashcards.** SM-2 spaced-repetition decks with a dedicated library, deck details, editor, and tap-to-flip study mode; teachers create decks and review submissions on the web dashboard. Optional subtle animations ship behind a Settings toggle (off by default).
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

22 focused router modules plus `zim_handler.py`, covering auth, student sync, teacher analytics, course management, content CRUD, media streaming, account management, passwords, audit logs, system health, and ZIM serving. The route-by-route reference is the OpenAPI spec at `/docs` when the server runs; module responsibilities are documented in docstrings under `Debian Server/app/routers/`.

Operational details:

- **Soft-delete lifecycle.** Deleting a resource sets `status = 'deleted'` plus `deleted_at` (30-day recycle bin); an hourly purge hard-deletes file and row. Deleted resources vanish from catalog and search but stay reachable by direct ID.
- **Rate limiting.** Per-IP token bucket at 200 requests/minute (configurable), exempting localhost, static assets, `/ping`, and ZIM GETs; ZIM uploads are separately capped.
- **Content standards.** Uploads validate against a controlled subject taxonomy and grades 1 to 13 (0 reserved for pre-primary, 13 for bridging and exam prep), require source and license metadata, and reject duplicates on `title + subject + grade + language + resource_type` with a `409` response plus an explicit `force_upload` override.
- **Audit logging.** Admin actions and resource status transitions append to `data/admin_actions.log` with UTC timestamps and acting user IDs; retention is configurable.
- **No external dependencies.** The server starts and serves every endpoint with no internet connection; `setup_hub.sh` provisioning is idempotent and completes offline after the initial package pass.
- **Security hardening.** Admin password randomly generated on first boot. Teachers can only edit/delete their own resources (admin override via `can_manage_resource()`). CORS tightened to specific methods and headers. GZip compression on JSON responses >500 bytes (skips Range requests for streaming). Password strength validation enforced on all new accounts. Profile icon uploads require authentication.

### Web dashboard

An 11-page vanilla HTML/CSS/JS teacher and admin dashboard served from the hub: dashboard, courses, students, student detail, content manager, flashcards, danger zone, settings, help, welcome (captive portal), error. Role-based access is enforced server-side on each page; students only reach the captive portal. All 11 pages are fully translated with client-side debounced search inputs.

---

## API / Interface Overview

Routes are grouped by prefix: student- and teacher-facing routes live under `/api`, `/student`, `/teacher`; captive-portal and health routes are public. The authoritative route list is the OpenAPI spec served at `/docs` (and `/redoc`) when the server is running; a static count here would go stale.

Notable endpoint behaviours:

- **Streaming.** Video files are served through `/api/stream/` with HTTP Range support (206 Partial Content) so students can seek without full download. The server does not transcode; target phones decode in hardware.
- **Auth.** JWT-style session tokens with the three-tier renewal described above; newly registered students are forced through a password change. Passwords are bcrypt-hashed server-side; the offline-only login path uses a separate local SHA-256 credential that never shares the server hash.
- **ZIM serving.** HTML from `/zim/page` has asset paths rewritten to `/zim/asset` endpoints that read lazily from the `.zim` binary; article search is capped at 500 results. An hourly auto-cleaner prunes archives by LRU policy against `zim_cache_config.json`.

The full OpenAPI spec is served at `/docs` when the server is running; the route inventory changes too often to duplicate here.

---

## Data Model

Server: a single SQLite file at `data/hub.db` in WAL mode. All access goes through `app/async_db.py` helpers, which run queries in a thread pool (`asyncio.to_thread`) so the event loop stays free; `db_conn()` is reserved for multi-statement transactions.

The authoritative schema, spanning accounts and auth tiers, resources, ZIM metadata, courses, quizzes, flashcards, and analytics tables, lives in [`Debian Server/app/database.py`](Debian%20Server/app/database.py). Do not trust a summary here over that file.

Client: the Flutter app mirrors catalog and progress state in its own local SQLite (schema version 17, migration chain from v2); see `EduMesh-Android/lib/core/storage/db_helper.dart`.

---

## Performance Data

Design targets (cold start ≤ 4 s, cached catalog load ≤ 800 ms, 0 jank frames, single-resource query ≤ 50 ms, release APK ≤ 25 MB) are tracked in `AGENTS.md`. The 250-concurrent-student concurrency target is a design figure validated only at small scale. A repeatable benchmark harness is not in scope for the PoC.

---

## Engineering Trade-offs

**SQLite over PostgreSQL.** WAL-mode SQLite handles the write patterns of a classroom on a Celeron with 2 GB RAM and is zero-configuration for non-DBA teachers. The cost is single-writer concurrency, which sets a practical ceiling around 100+ students before migration becomes necessary. The DB layer is isolated behind `async_db.py` so a PostgreSQL migration is a contained change rather than a rewrite.

**500-article ZIM search cap.** Kiwix archives hold hundreds of thousands of articles; loading them all would OOM a 1 GB phone. Capping search at 500 results guarantees the app never crashes on query, at the cost of requiring multiple queries for deep research across large archives.

**Test coverage vs. offline reliability.** Development time went to offline reliability (mutation queue, download atomicity, Keystore recovery) rather than test volume. The server suite is 64 tests across 7 files; the Flutter suite is 56 tests across 7 files (scheduler, flip card, animation system, profile flows, profile switcher, course model, smoke): enough to make refactoring safe, not exhaustive. This was the correct trade-off for a PoC.

**`.part` rename on FAT32.** The download rename is not atomic on FAT32/exFAT, the filesystems on most cheap SD cards. The `.part` convention still prevents corrupted files from masquerading as complete, and a crash mid-rename leaves at most one orphaned file. Writing to a temp directory and moving has the same fundamental limitation on these filesystems.

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
flutter test                         # 56 tests
flutter gen-l10n                     # Regenerate localizations after ARB changes
cd "Debian Server" && pytest         # 64 tests
```

---

## Roadmap

This is a proof of concept. It is done.

| Area | Status |
|---|---|
| Student app core (browse, download, view, offline) | Shipped |
| Courses, quizzes, flashcards (SM-2) | Shipped |
| Teacher/admin web dashboard, 6-language i18n | Shipped |
| ZIM/Kiwix offline article browsing | Shipped |
| Phone-to-phone sharing (ShareServer) | Shipped |
| Profile isolation and security hardening | Shipped |

The following were explicitly cut from scope. They are not defects; they are not next steps:

- 250-student concurrency load test (design target, not validated at scale)
- `task_queue.py` + `thumb_worker.py` background workers
- `encryption.py` (`EncryptedAPIRoute` for sensitive aggregates)
- Pre-primary to Grade 13 expansion
- Multi-week field deployment testing

The authoritative shipped/cut/open tracker is [`feature-roadmap.md`](Markdown%20files/feature-roadmap.md).

---

## Documentation

- [`docs/`](docs/): ADRs, ZIM search redesign notes, and the i18n debt tracker.
- [`feature-roadmap.md`](Markdown%20files/feature-roadmap.md): authoritative shipped/cut/open tracker.

Other working documents (engineering contract, design system, implementation details) live in the repo but are intentionally untracked; ask a maintainer for pointers.

---

## Contributing and Credits

College project submission. Rishi Raj set the architecture and technical direction, and wrote the FastAPI server, the full web dashboard, and the deployment tooling. Felice George wrote the Flutter mobile dashboard and led UI/UX and accessibility work. The offline-first data layer (catalog cache, mutation/download queues, connectivity) is joint work with Rishi Raj as primary author.

This proof of concept is complete. The codebase is stable and functional as shipped. No further development is planned.

---

## License

MIT — see [LICENSE](LICENSE) for the full text, including third-party dependency
notices (Dart/Python packages, bundled Noto fonts under SIL OFL, NCERT content
under its own license).