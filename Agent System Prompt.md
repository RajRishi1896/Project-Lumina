### **Project Lumina: Agent Implementation Guidelines**

**Objective:** Maintain and extend the "Edu-Mesh Scholar" application, focusing on a premium "Digital Scholar" aesthetic, offline-first reliability, and extreme performance optimization for low-spec hardware.

#### **1. Visual Design & Aesthetic**
*   **Typography:** Exclusively use **Atkinson Hyperlegible** (Google Fonts) for maximum accessibility.
*   **Color Palette:** Deep Navy (`#002045`), Academic Teal (`#13696A`), Scholar Yellow (`#F8BC4B`), and Soft Cream (`#F9F9FF`).
*   **UI Philosophy:** Use "Bento-style" status cards, high-contrast borders (2px), and subtle micro-animations. Avoid generic Flutter colors; use predefined `LuminaColors`.

#### **2. Architecture & File Management**
*   **Monolithic Screens:** Keep each major screen (e.g., `WelcomePage`, `DashboardPage`) in a **single, self-contained file**. Do not fragment UI components into separate files unless they are universal shared widgets.
*   **Universal Settings:** Always use the `LuminaSettingsSheet` widget for any settings trigger. It must include theme switching, profile management, and session logout.

#### **3. Security & Authentication**
*   **Identity Protection:** Never store passwords in plain text. Use **SHA-256 hashing** (via `crypto` package) before storage.
*   **Encrypted Storage:** Use `flutter_secure_storage` for all sensitive user data (UID, hashed credentials).
*   **Session Persistence:** Check for an existing session in `main.dart` to bypass the onboarding flow for returning scholars.

#### **4. Connectivity & "Zero-Cloud Guard"**
*   **No External Dependencies:** Strictly forbid dependencies requiring Google Play Services, Firebase Core, or remote CDN asset fetching. All functionality must reside within the local Mesh network.
*   **Connection Gate:** Use the `ConnectionGate` wrapper for mesh network interruptions. Connectivity checks must be deferred until **after** authentication.
*   **Messaging:** Never say "No Internet." Use **"Local Network Active"** or **"No Internet Connection Required!"**.

#### **5. Performance & Memory Hardening (Low-Spec Device Constraints)**
*   **Optimized Assets:** Use only optimized **SVGs** or compressed **WebP** files. High-resolution PNGs/JPEGs are forbidden to prevent memory exhaustion on 1GB-2GB RAM devices.
*   **ListView Hardening:** Always use `ListView.builder` for catalog listings. You must include explicit `itemExtent` or `prototypeItem` properties to prevent memory allocation spikes during scrolling.
*   **Resource Monitoring:** Dynamically calculate local storage usage, ensuring the **APK size** is included in the reported total for realistic hardware transparency.

#### **6. Technical Protocol**
*   **Build Workflow:** Always run `flutter analyze` and resolve all `error` and `warning` level issues before attempting a build.
*   **Release Optimization:** Compile using `flutter build apk --release` to ensure tree-shaking and resource optimization are active.

***

**Core Instruction to Agent:**
"Review the `LuminaSettingsSheet`, `ConnectionGate`, and `AuthService` before implementing new features. Strictly adhere to the **Performance & Memory Hardening** rules to ensure the app remains functional on budget Android hardware without any cloud reliance."