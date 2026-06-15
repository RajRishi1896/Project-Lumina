# Implementation Details

### Double-back-to-exit (`app_shell.dart:43-62`)
`PopScope` with a 2-second window. First back press shows a floating SnackBar ("Press back again to exit") with an Exit button. Second press within 2 seconds calls `SystemNavigator.pop()`. Prevents accidental exits while making intent clear.

### ZIM search limit (`search_page.dart:91-93`)
ZIM article fetching uses `'limit': '500'`. Kiwix ZIM archives can contain hundreds of thousands of articles. Loading them all would OOM a 1 GB RAM phone. A 500-article ceiling gives a representative sample.

### Connectivity heartbeat (`connectivity_service.dart:46-50`)
A `Timer.periodic` fires every 30 seconds to keep battery impact minimal. The HTTP `/ping` call has a 4-second timeout. Combined with platform-level events from `connectivity_plus`, the app detects disconnection within ~2 seconds (instant platform event) or at worst 34 seconds (platform missed it, heartbeat catches it).

### Activity sync debouncing (`activity_tracker.dart:26`)
The auto-sync timer fires every 60 seconds. `logAction()` writes directly to `SharedPreferences` (fast, synchronous). The 60-second cadence batches events for the server. `logKeyAction()` is identical to `logAction()` because the original debounce was never wired up. Simpler to reason about without the extra timer.

### Atomic downloads via `.part` pattern (`download_service.dart`)
Files download to `{filename}.part` first. On success, renamed to `{filename}`. On failure, the `.part` file is deleted. This prevents corrupted partial files from appearing as completed downloads. The rename isn't truly atomic on FAT32/exFAT (common on SD cards in low-end phones), but the `.part` convention means a crash during rename leaves at most one orphaned `.part` file rather than a misleadingly complete-looking file.

### Wake lock during transfers (`download_service.dart`, `student_profile_page.dart`)
`WakelockPlus.enable()` is called before file downloads and profile icon uploads. The comment reads "EDGE CASE: Prevent Pocket Sleep WiFi Drops". On low-end phones, putting the phone in a pocket during a transfer would trigger sleep, killing WiFi.

### Local-only auth with SHA-256 (`auth_service.dart`)
The app stores a local SHA-256-hashed user list in `FlutterSecureStorage` for offline authentication. When the hub is unreachable, credentials match against this local hash and return `'local_only'` mode. The student can still browse saved content and view cached analytics. Server-side auth uses bcrypt, completely separate.

### Secure storage crash recovery (`auth_service.dart:_getUsers`)
`FlutterSecureStorage` on Android throws if a student removes their lock screen (Keystore invalidates stored keys). `_getUsers()` catches this, calls `deleteAll()` to clear corrupt state, and lets the next login rebuild fresh. Without this guard, the app would crash-loop on every start.

### Mtime-based staleness detection (`resource_detail_page.dart`)
Before opening a locally-downloaded file, the app compares the file's mtime (from the `downloads` DB table) against the server's mtime (from the catalog). If the server version is newer, it re-downloads the resource automatically.

### Recommendation engine (`search_page.dart:_computeRecommendations`)
Every resource gets a score:

- +3 if it matches the student's grade
- +2 if the subject was previously accessed
- +1 if the resource type matches the student's most-frequent type

Top 6 scored resources show as "Recommended for You".

### Triple data fallback (`resource_detail_page.dart`, `search_page.dart`)
Every resource lookup tries three sources in order: (1) server API for live data, (2) `CatalogService` SQLite cache, (3) `DBHelper` downloads table for local files. Undownloaded resources appear as ghost items at 50% opacity when offline.

### Inline SVG hero illustration (`welcome_page.dart:_illustrationSvg`)
~240 lines of hardcoded SVG XML as a Dart string constant, rendered via `flutter_svg`. Depicts a classroom with students and a teacher. No external asset fetch, renders immediately on cold start.

### 5-tab bottom navigation (`app_shell.dart`)
Five tabs: Dashboard, Browse, Saved, Profile, and Students (teacher monitor). All tabs always visible regardless of role. No teacher-only gating.

### 3-tier token renewal chain (`api_client.dart:75-101`)
On 401/403, the interceptor tries three strategies in sequence:

1. `refreshSession()` using `refresh_token` (7-day expiry)
2. `renewSession()` using `persistent_key` (365-day expiry)
3. `logout()` to force re-authentication

### 5-second stats cache (`system_stats.py`)
The `/stats` endpoint caches its result for 5 seconds. Without this, every dashboard page load re-queries `COUNT(*)` from SQLite and `shutil.disk_usage()`. With it, rapid page refreshes don't hit the DB.

### ZIM auto-cleaner with configurable limits (`zim_auto_cleaner.py`, `lib/zim_settings.py`)
Runs hourly. Prunes the oldest HTML pages when total exceeds `max_pages` (default 500, configurable via `zim_cache_config.json`). Settings (`retention_days`, `max_pages`) stored in a JSON file with thread-safe getters/setters protected by `threading.Lock`.

### Battery reading from sysfs (`system_stats.py:52-59`)
The hub reads battery percentage from Linux sysfs (`/sys/class/power_supply/BAT0/capacity`) and includes it in `/stats`. Useful for teachers running the hub on an unplugged laptop in classrooms with unreliable power.

### Private helper classes for page-scoped state
Several large Flutter pages use private classes instead of leaking state into the global namespace:

- `_ScoredResource` (search_page.dart) – resource with recommendation score
- `_SubjectTime` (student_profile_page.dart) – subject name, minutes, colour for breakdown charts
- `_LanguageButton` and `_StatusItem` (welcome_page.dart) – language selector tile and hub-status indicator

### Download exponential backoff (`download_queue.dart:108-110`)
```dart
final retryCount = 5 - task.retries;
final delay = Duration(seconds: 3 * (1 << retryCount)); // 3, 6, 12, 24, 48
```

5 retries with exponential backoff: 3, 6, 12, 24, 48 seconds. After the 5th failure, a notification says "Download failed" and the item leaves the queue. Transient network blips common in school WiFi resolve without manual intervention.

### Mutation queue max retries (`mutation_queue.dart:62-68`)
3 retries per mutation, then the record is deleted from `pending_mutations` and logged. Unlike downloads, mutations are tiny JSON payloads. If they fail 3 times, something is fundamentally wrong (wrong endpoint, bad data). Retrying indefinitely would mask bugs.

### Video black-intro skip (`thumb_worker.py:86-109`)
```python
detect = subprocess.run([
    "ffmpeg", "-i", filepath,
    "-vf", "blackdetect=d=0.5:pix_th=0.1",
    "-f", "null", "-",
], capture_output=True, text=True, timeout=30)
```

The `blackdetect` filter finds black segments (duration >= 0.5s, pixel threshold 0.1). The code picks the first `black_start` timestamp, adds 1 second to land on actual content, then caps at 30 seconds to avoid picking an ending frame. Many educational videos start with a black title card; this avoids showing a black thumbnail.

### Mini-player singleton (`mini_player_controller.dart`)
`MiniPlayerController` is a singleton holding references to `VideoPlayerController` and `ChewieController`. When the user navigates back from full-screen video, the controllers aren't disposed. They transfer to the overlay `MiniPlayerWidget`, so playback continues uninterrupted. Closing the overlay calls `dispose()` on both.

### Catalog sync in a transaction (`catalog_service.dart:26-41`)
```dart
await db.transaction((txn) async {
  txn.delete('catalog');
  for (final item in data) {
    txn.insert('catalog', { ... });
  }
});
```

The entire catalog is replaced in a single transaction. If the sync fails midway (hub drops), the old catalog stays intact. No window where the user sees an empty cache.

### `last_accessed` throttle (`dependencies.py:102-107`)
```python
if row[2] is None or _is_stale_minutes(row[2], 5):
    cur.execute("UPDATE sessions SET last_accessed = datetime('now') ...")
```

Updating `last_accessed` on every request would hammer the DB. The 5-minute staleness check drops the update rate from ~1 per request to ~12 per hour per user. Roughly a 99.7% reduction with 30 students hitting the server every 60 seconds.

### Session pruning (`api.py:61-73`)
A background task runs every hour, deleting sessions not accessed in 7 days, used or expired refresh tokens, and expired persistent keys. Keeps the `sessions` table small even if students never log out explicitly (common with shared devices).

### Admin log retention (`database.py:36-95`)
Configurable: 24h, 7d, 30d, 3m, 6m, never, none. Stored as a key-value pair in the `settings` table. Pruning re-reads the log file line-by-line comparing timestamps, not by parsing structured data. This means the file is always valid even if partially corrupted.

### `EncryptedAPIRoute` and `NO_ENCRYPT_PATHS` (`encryption.py:18,21-36`)
```python
NO_ENCRYPT_PATHS = {"/student/token", "/register", ...}
```

Routes that bootstrap encryption (login, token refresh) and static content stay plaintext. The `EncryptedAPIRoute` class transparently wraps every other route with AES-256-GCM. The Flutter app's `ApiClient` sends `{"encrypted": "..."}` for POST/PUT and decrypts responses. No per-route encryption logic required.

### Resources v2 migration (`database.py:261-313`)
The original `resources` table had minimal columns (id, title, file_path, type). Version 2 adds: subject, grade, language, resource_type, filename, original_name, source, license, uploaded_by, uploaded_at, status, description, chapter, year, superseded_by. The migration creates a new table, migrates data with `COALESCE` for null safety, drops the old one, and renames. All in one connection to avoid lock contention.

### Profile icon with local fallback (`student_profile_page.dart`)
Profile icons upload to the hub (`/student/upload-icon`) and are stored in `profile_icons/`. The Flutter app downloads each icon and saves it to the app's documents directory. When offline, it serves the local copy. The profile picture shows even when the hub is unreachable.

### Admin log translation (`lumina.js`)
The server stores audit logs in English only. The web frontend translates them client-side via `translateLogMsg()` using regex patterns plus `__()` lookups. For example, `"Force password reset for student {name}"` extracts the student name via regex and looks up `__('settings.log.pwd_reset_student', {name})`.

### `data-i18n-data-label` for responsive tables (`lumina.js` + HTML)
Mobile-responsive tables use `data-label` attributes on `<td>` elements. Normal `data-i18n` would overwrite the cell's dynamic content. The solution: `data-i18n-data-label="key"` sets only the `data-label` attribute, while the inner content uses `__('key')` at render time. Table cells show student names correctly while the responsive layout shows the translated column header.

### Rate limit two tiers (`middleware.py:27,86-104`)
- **Strict paths** (`/token`, `/teacher`, `/register`, `/logout`, `/student/token`): 600 req/min per IP
- **General paths**: 3000 req/min per IP

Static file requests don't consume the strict tier's budget. Each record stores `(timestamp, is_strict)` separately. A login brute-forcer hitting `/token` 700 times in a minute gets blocked while other students can still load resources.

### Task queue with timeout (`task_queue.py`)
```python
_HANDLER_TIMEOUT = 300
_TASK_TTL = 3600
```

2 workers with a 5-minute handler timeout. Long enough for large thumbnail generation, short enough to prevent a stuck worker from blocking the queue forever. Completed and failed tasks are purged after 1 hour.

### mDNS beacon (`discovery.py:54-61`)
```python
info = ServiceInfo(
    "_http._tcp.local.",
    "EduMeshHub._http._tcp.local.",
    addresses=[socket.inet_aton(self.host_ip)],
    port=self.port,
    properties={'version': '1.0'},
    server="lumina-hub.local.",
)
```

Registers an `_http._tcp` service so any mDNS-capable client (Android, iOS, Linux) can discover the hub without knowing its IP. This is the fallback before DNS and static IP. Runs on the local subnet only. No external queries or registry services.

### Idempotent setup (`setup_hub.sh`)
Every provisioning step is idempotent: `mkdir -p`, conditional `apt install`, checks for existing file descriptor limits, conditional systemd service creation. The script can be re-run as a repair install without breaking existing configs. The only non-idempotent step is the nightly cron job, protected by `grep -v` on existing entries.
