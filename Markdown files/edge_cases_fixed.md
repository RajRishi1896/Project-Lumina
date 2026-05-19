# EduMesh Infrastructure & Edge Case Mitigation Specification

This specification documents the rigorous architectural safeguards, kernel-level optimizations, and client-side failsafes implemented within the **EduMesh** ecosystem. These mitigations are engineered to ensure multi-year, zero-maintenance survivability in severe, zero-bandwidth field deployments.

---

## 1. Hardware & Operating System Hardening (Debian Server)

- **Unattended Boot Corruption Recovery (`fsck.repair=yes`)**: Configured the GRUB bootloader to enforce automated, non-interactive filesystem checks (`fsck`). Upon unexpected power loss or improper shutdown, the kernel automatically repairs corrupted sectors without hanging on interactive terminal prompts.
- **Memory Leak Mitigation & System Refresh**: Configured a scheduled systemd/cron daemon to execute an automated, graceful reboot nightly at 03:00 AM. This flushes orphaned memory allocations, resets network interface buffers, and guarantees persistent Day-1 performance.
- **Disk Exhaustion Protection**: Implemented a mandatory pre-flight storage check within the FastAPI application layer. The server automatically rejects incoming file uploads if free disk space drops below 2.0 GB, preventing SQLite Write-Ahead Log (WAL) corruption and subsequent kernel panics.

---

## 2. Network Infrastructure & Captive Portal Routing

- **Captive Portal Persistence (`204 No Content` Interception)**: Deployed a dedicated `/generate_204` endpoint alongside wildcard DNS routing (`address=/#/192.168.1.1`) via `dnsmasq`. This successfully intercepts mobile operating system connectivity probes, preventing Android and iOS devices from aggressively disconnecting from the local Wi-Fi in search of cellular data.
- **DHCP Pool Optimization**: Expanded the local `dnsmasq` DHCP allocation pool from `192.168.1.10` to `250` with an aggressive 2-hour lease duration. This ensures rapid IP recycling, preventing pool exhaustion during high-density student onboarding sessions.

---

## 3. Database Concurrency & API Security (SQLite3 & FastAPI)

- **High-Concurrency Queueing (`busy_timeout`)**: Configured SQLite connections with a strict 5,000ms busy timeout. When dozens of client devices execute simultaneous synchronization requests, transactions queue synchronously rather than throwing fatal `SQLITE_BUSY` ("Database is locked") exceptions.
- **Rate-Limiting Middleware**: Deployed custom token-bucket rate-limiting middleware across all public student API endpoints, capping inbound traffic at 20 requests per minute per IP address to prevent denial-of-service anomalies and database flooding.
- **Write-Ahead Log Truncation**: Integrated automated `PRAGMA wal_checkpoint(TRUNCATE)` execution on application startup to systematically commit and truncate high-speed transaction logs, preventing disk bloat.

---

## 4. Kernel Resource Limits & Administrative Failsafes

- **File Descriptor Scaling (`ulimit`)**: Elevated the Linux system file descriptor ceiling (`fs.file-max`) to `65,535` via the provisioning orchestration script. This eliminates `EMFILE` ("Too many open files") crashes during concurrent large-scale media streaming.
- **Administrative Account Failsafe (`reset_admin.sh`)**: Deployed a standalone, executable administrative recovery script. In the event of credential loss in an offline environment, administrators can execute this script to restore default cryptographically hashed credentials (`lumina2026`).
- **Idempotent Orchestration**: Engineered `setup_hub.sh` with strict conditional verification (`grep -q`) prior to modifying system configuration files (`limits.conf`, `crontab`, `grub`). This ensures repeated executions do not result in duplicate configurations or corrupted boot sequences.

---

## 5. Mobile Client Resiliency (Android / Flutter)

- **Offline Synchronization Queue Capping**: Implemented an automated pruning mechanism within the local Hive/SQLite caching layer. If an offline device accumulates over 1,000 pending telemetry events, the client systematically drops the oldest records to prevent `SharedPreferences` memory exhaustion.
- **Cryptographic Keystore Recovery**: Engineered robust error handling within `AuthService` to intercept `PlatformException` anomalies triggered by OS-level lock screen PIN modifications. Upon detecting keystore invalidation, the client automatically flushes corrupted secure storage (`deleteAll()`) to prevent permanent startup crashes.
- **Asynchronous Download Wakelocks**: Integrated `wakelock_plus` into `DownloadService` to maintain CPU wakefulness during large file transfers, preventing the mobile OS from throttling Wi-Fi radios when the device screen is locked.
- **Real-Time System Clock Validation**: Implemented pre-sync timestamp verification. If a depleted device battery resets the system RTC to a legacy epoch (e.g., `year < 2025`), the client blocks outbound sync payloads to preserve server-side analytics integrity.
- **Pre-emptive Storage Verification**: The download manager actively verifies available device storage prior to initiating file transfers, gracefully aborting with clear user feedback upon detecting impending storage exhaustion.
- **Atomic File Transactions (`.part` Isolation)**: Inbound downloads are isolated as temporary `.part` files until cryptographic verification passes at 100% completion. A dedicated startup garbage collector automatically purges orphaned `.part` files to prevent silent storage leaks.
- **Cleartext HTTP Enforcement**: Explicitly configured `android:usesCleartextTraffic="true"` within `AndroidManifest.xml` to guarantee seamless, unhindered communication with the local HTTP mesh network (`http://lumina.hub:8000`).

---

## 6. Storage & Routing Optimization

- **Filename Sanitization**: Implemented strict regex sanitization (`re.sub`) across all upload handlers, stripping spaces and non-alphanumeric characters to guarantee POSIX-compliant file paths and prevent client-side `404 Not Found` errors.
- **Deduplication Engine**: Uploading a file matching an existing asset's filename automatically triggers an atomic purge of the legacy file and its associated database pointers prior to committing the new binary, optimizing storage efficiency.
- **Explicit Route Resolution**: Established distinct, explicit routing definitions for root (`/`) and administrative (`/dashboard`) paths within FastAPI, preventing route ambiguity and ensuring clean separation of concerns.

---

## 7. Professional UI/UX & Human Factors

- **Visual Asset Professionalization**: Replaced informal graphical elements with highly optimized, institutional-grade SVG iconography across the Teacher Web Dashboard.
- **Persistent Ergonomic Dark Mode**: Deployed a fully integrated, low-contrast dark palette (Catppuccin specification) backed by local storage persistence, reducing visual fatigue during low-light administrative operations.
- **Fluid State Transitions**: Implemented hardware-accelerated CSS transitions (`0.3s ease-in-out`) across all interactive DOM elements to ensure seamless, non-jarring UI state changes.
- **Autonomous User Onboarding**: Embedded comprehensive, interactive offline documentation directly within the client application, providing immediate operational guidance without requiring external internet access.
- **Real-Time Telemetry Dashboards**: Built real-time disk and battery health telemetry monitors into the Welcome Portal and Admin Dashboard, utilizing color-coded thresholds for rapid system status verification.
