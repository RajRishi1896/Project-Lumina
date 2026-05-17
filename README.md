# Project Lumina: EduMesh
**The Offline-First Educational Mesh Network**

## 🌍 About the Project
Project Lumina is a high-resilience, fully offline educational ecosystem designed for zero-bandwidth environments. It enables schools to host their own private "educational internet" where students can download textbooks and watch lecture videos without ever touching the global web.

---

## 📁 Repository Structure
The project is organized into three primary pillars:

| Component | Location | Description |
| :--- | :--- | :--- |
| **Debian Server** | `[Debian Server/](file:///Project%20Lumina/Debian%20Server/)` | The Hub backend, Wi-Fi management scripts, and Web Dashboard. |
| **App Source** | `[EduMesh-Android/](file:////Project%20Lumina/EduMesh-Android/)` | The Flutter source code for the student mobile application. |

---

## 🚀 Quick Start Guide

### 1. Prepare the Hub (Server)
1. Install **Debian 12** on a dedicated laptop or mini-PC.
2. Navigate to the `Debian Server/` folder and run `sudo ./setup_hub.sh`.
3. The server will now broadcast the **EduMesh** Wi-Fi network.
4. *Detailed instructions:* See the [README_SERVER.md](file:///c:/Users/Rajri/Desktop/Idea%20Lab/Project%20Lumina/Debian%20Server/README_SERVER.md).

### 2. Prepare the App (Android)
1. In the `EduMesh-Android/` folder, run `flutter build apk --release`.
2. Move the compiled APK to the Hub's `uploads/` folder.
3. Students can now download the app by connecting to the Wi-Fi and visiting `http://lumina.hub:8000`.

---

## 🛡️ Engineering & Resilience
This system is hardened against extreme field conditions:
- **Database Safety**: Enforced SQLite WAL mode and timeout logic.
- **Power Failure**: Auto-repairing `fsck` boot sequence and nightly RAM flushes.
- **Connectivity**: Captive portal interception to prevent "No Internet" drops.

For a full list of the 25+ edge cases mitigated in this build, check out the [edge_cases_fixed.md](file:///c:/Users/Rajri/Desktop/Idea%20Lab/Project%20Lumina/Markdown%20files/edge_cases_fixed.md).

---
*Project Lumina: Empowering scholars in zero-bandwidth environments.*
