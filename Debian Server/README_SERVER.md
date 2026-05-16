# EduMesh Hub: Server Internals & Documentation

This folder contains the core logic and deployment scripts for the **EduMesh Hub**, a headless Debian-based offline server.

## 🏗️ Architecture Overview
The Hub acts as a multi-functional appliance:
- **DHCP/DNS Server**: Manages the local Wi-Fi network and intercepts captive portal requests.
- **File Host**: Serves the EduMesh APK and educational resources via `FastAPI`.
- **Database (SQLite)**: Tracks student identities, resource metadata, and synchronization logs.

## 📁 Directory Structure
- `app/`: Contains the FastAPI backend logic (`api.py`) and service discovery.
- `static/`: The web frontend for the Teacher Dashboard (`index.html`) and Student Welcome Page (`welcome.html`).
- `data/`: Holds the SQLite database (`hub.db`) and system logs (`hub.log`).
- `uploads/`: The physical storage location for all educational PDFs and videos.

## 🚀 Key Deployment Scripts
| Script | Purpose |
| :--- | :--- |
| **`setup_hub.sh`** | The master idempotent installer. Configures dependencies, networking, and system limits. |
| **`reset_admin.sh`** | An emergency failsafe to hard-reset the teacher dashboard password via terminal. |
| **`hub_health_check.sh`** | Diagnoses network, storage, and service status. |
| **`set_static_ip.sh`** | Configures the Hub with a fixed IP address for consistent network routing. |

## 🌐 API Endpoints (FastAPI)
The Hub operates on port **8000**:
- `GET /`: The Student Welcome Portal.
- `GET /dashboard`: The Teacher Administration Panel.
- `GET /resources`: Lists all available educational materials.
- `POST /teacher/upload`: Secure endpoint for adding new resources.
- `POST /sync/activity`: Inbound sync for student reading/viewing history.
- `GET /generate_204`: Captive portal "Fake Internet" interceptor.

## 🛠️ Maintenance & Hardening
- **Auto-Repair**: GRUB is configured with `fsck.repair=yes` to fix file system corruption automatically on boot.
- **Stability**: A cron job reboots the system every night at 3:00 AM to flush memory and reset network drivers.
- **Database**: SQLite is tuned with **WAL (Write-Ahead Logging)** mode for high-concurrency access.

---
*For the main project documentation, refer to the README in the root directory.*
