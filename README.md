# Project Lumina: EduMesh
**Offline-First Educational Mesh Infrastructure**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Platform: Debian | Android | Flutter](https://img.shields.io/badge/Platform-Debian%20%7C%20Android%20%7C%20Flutter-academicTeal.svg)]()
[![Architecture: Offline-First | Mesh](https://img.shields.io/badge/Architecture-Offline--First%20%7C%20Mesh-F8BC4B.svg)]()

---

## Executive Summary

**Project Lumina (EduMesh)** is an offline educational server designed for zero-bandwidth environments. Deployed on repurposed Debian 12 laptops, it broadcasts a local Wi-Fi hotspot that serves educational content—textbooks, video lectures, Wikipedia archives, and practice materials—to Android smartphones without internet access.

```
+-------------------------------------------------------------------+
|                        LUMINA EDUMESH HUB                         |
|     (Debian 12 Appliance / Hotspot / Captive Portal / FastAPI)    |
+---------------------------------+---------------------------------+
                                  |
            +---------------------+---------------------+
            | (Local Wi-Fi / UDP Discovery / 0.0.0.0:8000)
            v                                           v
+-----------------------+                   +-----------------------+
|  SCHOLAR ANDROID APP  |                   |   TEACHER WEB PORTAL  |
|  (Flutter Client /    |                   |   (Responsive HTML5 / |
|   Offline Cache)      |                   |    Resource Manager)  |
+-----------------------+                   +-----------------------+
```

---

## System Architecture & Repository Structure

The repository is organized into three parts:

| Pillar | Filepath / Directory | Core Responsibilities & Technologies |
| :--- | :--- | :--- |
| **1. Infrastructure Hub** | `Debian Server/` | - Headless Debian 12 management scripts (`setup_hub.sh`)<br>- FastAPI / Uvicorn backend REST APIs (`app/api.py`)<br>- SQLite3 WAL-mode database (`data/hub.db`)<br>- Captive portal DNS/IP routing (`static/welcome.html`) |
| **2. Mobile Client** | `EduMesh-Android/` | - Flutter 3.x cross-platform mobile application<br>- Local SQLite/Hive caching & offline synchronization (`SyncService`)<br>- UDP Broadcast Service Discovery (`DiscoveryService`)<br>- Zero-config Demo Mode (`AuthService`) |
| **3. Engineering Specs** | `Markdown files/` | - Technical notes (`edge_cases_fixed.md`)<br>- Deployment notes and recovery guides |

---

## Deployment & Operational Runbook

### Phase 1: Hub (Debian Server) Provisioning
1. **OS Installation**: Install a clean, minimal instance of **Debian 12 (Bookworm)** on the designated server hardware (mini-PC or laptop).
2. **Automated Orchestration**:
   ```bash
   cd "Debian Server"
   sudo ./setup_hub.sh
   ```
   *Note: This script is fully idempotent. It configures `NetworkManager` for hotspot broadcasting, establishes `iptables` rules for captive portal redirection, sets up the Python virtual environment, and installs the `lumina-hub.service` systemd daemon.*
3. **Verification**: Verify the service status using systemd:
   ```bash
   systemctl status lumina-hub.service
   ```
4. **Detailed Server Documentation**: Consult [`Debian Server/README_SERVER.md`](./Debian%20Server/README_SERVER.md) for advanced network tuning and API contracts.

### Phase 2: Mobile Client (Android APK) Compilation
1. **Environment Setup**: Ensure the Flutter SDK and Android NDK/SDK toolchains are installed and configured.
2. **Release Build**:
   ```bash
   cd EduMesh-Android
   flutter build apk --release
   ```
3. **Distribution**: Copy the generated binary from `build/app/outputs/flutter-apk/app-release.apk` into the server's `uploads/` directory as `EduMesh.apk`. 
4. **Client Onboarding**: Connecting devices will automatically be intercepted by the captive portal at `http://lumina.hub:8000`, directing them to download the latest APK directly from the local server.

---

## System Resilience & Reliability

- **Database**: SQLite configured in WAL (Write-Ahead Logging) mode with 5-second busy timeout to prevent lock contention during concurrent syncs.
- **Power Outage**: GRUB bootloader configured with `fsck.repair=yes` for automatic filesystem repair after unexpected shutdowns.
- **Network Persistence**: Custom `/generate_204` endpoint prevents Android/iOS from dropping the Wi-Fi connection by simulating internet reachability.
- **Automated Maintenance**: Cron jobs perform nightly cleanup and network driver reset at 03:00 AM for sustained long-term operation.

---

## Documentation

- **[Edge Cases Mitigated](./Markdown%20files/edge_cases_fixed.md)**: Analysis of power, network, storage, and concurrency edge cases handled during development.
- **[Server Internals](./Debian%20Server/README_SERVER.md)**: FastAPI routes, systemd service management, and administrative scripts.

---
<div align="center">
  <b>Project Lumina • Engineered for Global Educational Equity</b>
</div>
