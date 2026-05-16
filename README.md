# Project Lumina: EduMesh-Android

**Project Lumina** is a high-fidelity, offline-first educational ecosystem designed for the **EduMesh** network. It provides scholars in low-connectivity or zero-internet environments with a premium, secure, and performant learning experience.

![Project Status](https://img.shields.io/badge/Status-Active-success)
![Platform](https://img.shields.io/badge/Platform-Android-blue)
![Privacy](https://img.shields.io/badge/Privacy-Zero--Cloud-brightgreen)

## 🏛️ Core Philosophies

### 1. The "Digital Scholar" Aesthetic
The UI is built on the **Atkinson Hyperlegible** typography system, ensuring maximum readability for students with varying visual needs. The design language uses a sophisticated "Bento-style" card system and an academic palette of Deep Navy, Scholar Yellow, and Academic Teal.

### 2. Zero-Cloud Guard
Project Lumina is physically incapable of "phoning home." We strictly forbid dependencies on Google Play Services, Firebase, or external CDNs.
*   **100% Data Sovereignty**: All user data stays on the device and the local mesh.
*   **Battery Hardening**: No background sync loops or cloud retries, maximizing device life in remote areas.

### 3. Performance for All
Engineered to run smoothly on budget Android hardware (1GB-2GB RAM):
*   **Memory Safety**: Universal use of `ListView.builder` with `prototypeItem` to prevent memory spikes.
*   **Optimized Assets**: Exclusively uses SVGs and WebP assets to minimize APK and RAM overhead.
*   **Live Hardware Monitoring**: Real-time tracking of disk space, including APK size, for total transparency.

## 🛠️ Tech Stack
*   **Core**: Flutter (Material 3)
*   **State Management**: Riverpod
*   **Security**: SHA-256 Hashing & Flutter Secure Storage
*   **Typography**: Google Fonts (Atkinson Hyperlegible)
*   **Responsive UI**: Flutter ScreenUtil

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK `^3.0.0`
*   Android Studio / VS Code
*   **No Internet Required** (once dependencies are fetched)

### Build Optimized APK
To generate a production-ready, tree-shaken binary:
```bash
flutter analyze
flutter build apk --release
```

## 🔐 Security & Identity
Identity is anchored to the local Mesh Hub. Scholar IDs follow the deterministic pattern of `HubID_UserSuffix`, ensuring a secure, locally-verifiable identity without requiring global cloud authentication.

---
*Built for the scholars of tomorrow, powered by the mesh of today.*
