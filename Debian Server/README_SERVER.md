# EduMesh Infrastructure Hub: Debian Server Internals & Architectural Specification

This document covers the system architecture, network services, and administrative procedures for the **EduMesh Hub** — a headless Debian 12 server.

---

## System Architecture & Core Daemons

The Hub combines network routing, RESTful APIs, and persistent storage in a single appliance:

- **DHCP & DNS Management (`dnsmasq`)**: Operates as the local gateway daemon, issuing IP addresses, managing DNS resolution, and executing captive portal DNS hijacking (`address=/#/192.168.1.1`).
- **RESTful API Backend (`FastAPI` / `Uvicorn`)**: Serves the core microservices layer on port `8000`, handling student authentication, telemetry synchronization, resource distribution, and the captive portal `204 No Content` interceptor.
- **Transactional Database (`SQLite3`)**: Stores student identities, encrypted teacher credentials, educational asset metadata, and offline telemetry queues using Write-Ahead Logging (WAL) for high concurrency.

---

## Repository & Directory Layout

- `app/`: Contains the core FastAPI application logic (`api.py`), middleware definitions, and UDP broadcast service discovery daemons.
- `static/`: Contains the fully responsive HTML5/CSS3 frontend assets for the Teacher Management Dashboard (`index.html`) and the Student Onboarding Portal (`welcome.html`).
- `data/`: Houses the high-speed SQLite transactional database (`hub.db`) and persistent system operational logs (`hub.log`).
- `uploads/`: The physical POSIX storage volume for all educational binaries, including Kiwix `.zim` archives, PDF textbooks, MP4 lecture media, and the distribution APK.

---

## Deployment & Administrative Scripts

| Automation Script | Operational Purpose & Execution Contract |
| :--- | :--- |
| **`setup_hub.sh`** | Automated provisioning script. Configures `NetworkManager` Wi-Fi hotspot broadcasting, establishes `iptables` captive portal redirection rules, elevates kernel file descriptor limits (`ulimit`), and installs the `lumina-hub.service` systemd daemon. |
| **`reset_admin.sh`** | Utility script. Resets the teacher administration password back to the default (`lumina2026`) via direct SQLite transaction. |
| **`hub_health_check.sh`** | Diagnostic utility for monitoring system vitals, validating `dnsmasq` leases, verifying `iptables` forwarding rules, and checking disk capacity thresholds. |
| **`set_static_ip.sh`** | Configures the primary wireless interface (`wlan0`) with a persistent static IP (`192.168.1.1`) to ensure stable mesh routing. |

---

## FastAPI Service Contract & REST Endpoints

The Uvicorn ASGI server binds to `0.0.0.0:8000` and exposes the following primary routing contracts:

- `GET /`: Captive portal landing page serving the Student Welcome Portal (`welcome.html`).
- `GET /dashboard`: Protected administrative interface serving the Teacher Management Dashboard (`index.html`).
- `GET /resources`: Returns a JSON catalog of all active educational assets and their local download URIs.
- `GET /files`: Returns an administrative manifest of physical files residing in the `/uploads` directory.
- `GET /ping`: Network connectivity probe utilized by the Android client gatekeeper to verify Hub reachability.
- `POST /teacher/upload`: Secure multipart upload handler featuring automatic filename sanitization and asset deduplication.
- `POST /sync/activity`: Inbound telemetry receiver for processing queued student reading and viewing histories.
- `GET /generate_204`: Captive portal "Fake Internet" interceptor designed to prevent mobile OS cellular fallback.

---

## Reliability Features

- **Filesystem Repair**: The Linux kernel boot parameters are permanently configured with `fsck.repair=yes`, enabling unattended recovery from sector corruption following sudden power outages.
- **Nightly Cleanup**: A scheduled systemd/cron job performs an automated system reboot every night at 03:00 AM, clears memory and resets wireless driver state.
- **Database Tuning**: SQLite is configured with Write-Ahead Logging (`PRAGMA journal_mode=WAL`) and a 5,000ms busy timeout to eliminate transaction locks during concurrent classroom syncs.

---
*For the root infrastructure overview and client compilation instructions, refer to the master README in the root directory.*
