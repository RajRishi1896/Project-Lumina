# Project Lumina: EduMesh
**Enterprise-Grade, Offline-First Educational Mesh Infrastructure**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Platform: Debian | Android | Flutter](https://img.shields.io/badge/Platform-Debian%20%7C%20Android%20%7C%20Flutter-academicTeal.svg)]()
[![Architecture: Offline-First | Mesh](https://img.shields.io/badge/Architecture-Offline--First%20%7C%20Mesh-F8BC4B.svg)]()

---

## Executive Summary

**Project Lumina (EduMesh)** is a highly resilient, fully autonomous educational ecosystem engineered specifically for zero-bandwidth, disconnected environments. Designed for deployment in rural schools, remote field stations, and developing regions, EduMesh enables institutions to establish a self-healing, localized "educational internet." 

Through this private micro-cloud, students can access rich interactive textbooks, high-definition lecture videos, and Wikipedia archives via their mobile devices—without requiring an active connection to the global internet.

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

The repository is structured into three primary architectural pillars, cleanly separating the backend appliance infrastructure, the mobile application client, and system engineering documentation:

| Pillar | Filepath / Directory | Core Responsibilities & Technologies |
| :--- | :--- | :--- |
| **1. Infrastructure Hub** | `Debian Server/` | - Headless Debian 12 management scripts (`setup_hub.sh`)<br>- FastAPI / Uvicorn backend REST APIs (`app/api.py`)<br>- SQLite3 WAL-mode database (`data/hub.db`)<br>- Captive portal DNS/IP routing (`static/welcome.html`) |
| **2. Mobile Client** | `EduMesh-Android/` | - Flutter 3.x cross-platform mobile application<br>- Local SQLite/Hive caching & offline synchronization (`SyncService`)<br>- UDP Broadcast Service Discovery (`DiscoveryService`)<br>- Zero-config Demo Mode (`AuthService`) |
| **3. Engineering Specs** | `Markdown files/` | - In-depth technical specifications (`edge_cases_fixed.md`)<br>- Deployment runbooks and disaster recovery guides |

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
4. **Detailed Server Documentation**: Consult [`Debian Server/README_SERVER.md`](file:///c:/Users/Rajri/Desktop/Idea%20Lab/Project%20Lumina/Debian%20Server/README_SERVER.md) for advanced network tuning and API contracts.

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

## Enterprise Hardening & Resilience Engineering

EduMesh is designed to withstand severe field-level anomalies, power grid instability, and hardware degradation:

- **Database Integrity**: SQLite is explicitly configured in **WAL (Write-Ahead Logging)** mode with strict 5-second busy timeouts to ensure zero corruption during concurrent multi-client syncs.
- **Power Outage Resilience**: The operating system bootloader (`GRUB`) is hardcoded with `fsck.repair=yes` to perform automated, unattended filesystem repairs following abrupt power cuts.
- **Network Persistence**: Built-in `/generate_204` endpoints trick Android/iOS devices into recognizing a valid internet connection, preventing modern mobile OS daemons from dropping the Wi-Fi connection in search of cellular data.
- **Automated Maintenance**: Scheduled cron jobs execute nightly memory flushes and network driver resets at 03:00 AM to guarantee continuous, month-over-month uptime without human intervention.

---

## Comprehensive Documentation

For an exhaustive technical breakdown of the 25+ specific field-tested edge cases mitigated in this production release, please review our core engineering documentation:
- **[Edge Cases Mitigated](file:///c:/Users/Rajri/Desktop/Idea%20Lab/Project%20Lumina/Markdown%20files/edge_cases_fixed.md)**: Detailed analysis of power, network, storage, and concurrency solutions.
- **[Server Internals](file:///c:/Users/Rajri/Desktop/Idea%20Lab/Project%20Lumina/Debian%20Server/README_SERVER.md)**: Deep dive into FastAPI routes, systemd daemons, and administrative recovery scripts.

---
<div align="center">
  <b>Project Lumina • Engineered for Global Educational Equity</b>
</div>
