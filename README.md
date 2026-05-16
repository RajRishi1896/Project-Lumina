# Project Lumina: EduMesh
**The Offline-First Educational Mesh Network**

## 🌍 About the Project
EduMesh is a military-grade, fully offline educational ecosystem designed to operate in low-resource environments, developing nations, and disaster zones. It consists of two main components:
1. **The Hub (Debian Server)**: A headless server that acts as a local Wi-Fi router, database, and file host.
2. **The Scholar App (Android/Flutter)**: A companion mobile application that allows students to download textbooks, watch educational videos, and sync their progress locally—without ever touching the global internet.

The system is heavily fortified against power losses, hardware storage limits, memory leaks, and concurrent network stress, making it capable of running unattended for years.

---

## ⚙️ How to Set it All Up

### Step 1: Build the Android App
Before deploying the server, you need to compile the Android App so you can load it onto the Hub.
1. Ensure the Flutter SDK is installed on your computer.
2. Open the `EduMesh-Android` folder in your terminal.
3. Fetch dependencies and build the release APK:
   ```bash
   flutter pub get
   flutter build apk --release
   ```
4. Find the compiled APK at `build/app/outputs/flutter-apk/app-release.apk`. Rename this file to `EduMesh.apk`.

### Step 2: Deploy the Hub (Debian Server)
1. Install a fresh copy of **Debian 12 (Bookworm)** on a dedicated laptop or mini-PC.
2. Transfer the `Debian Server` folder onto the laptop via a USB flash drive.
3. Open the terminal, navigate to the folder, and run the setup script:
   ```bash
   cd "Debian Server"
   chmod +x setup_hub.sh
   sudo ./setup_hub.sh
   ```
4. Once the setup completes, **reboot the laptop**. The laptop is now broadcasting the EduMesh Wi-Fi network!
5. *Important*: Copy the `EduMesh.apk` file you built in Step 1 and place it inside the `Debian Server/uploads/` directory on the Hub.

---

## 🚀 How to Use It

### 👨‍🏫 For Teachers (Managing the Hub)
As a teacher or administrator, you manage the network from any connected device (phone, tablet, or PC).
1. Connect to the Hub's Wi-Fi network.
2. Open a web browser and navigate to: `http://lumina.hub:8000/dashboard`
3. Log in using the default credentials:
   - **Username**: `admin`
   - **Password**: `lumina2026`
4. **Upload Resources**: Go to the "Uploads" tab to add PDFs, Videos, or Kiwix archives. These files are instantly made available to all students on the mesh.
5. **Change Password**: Go to the "Security" tab to change the default password.
   * *Emergency Reset*: If you forget your password, you can plug a monitor/keyboard into the Hub and run `sudo ./reset_admin.sh` to reset it back to `lumina2026`.

### 🎒 For Students (Getting & Using the App)
Students do not need internet access or a Google Play Store account to get the app. They simply download it directly from the Hub!

**How to Install the App:**
1. Turn on Wi-Fi and connect to the Hub's local network.
2. Open Google Chrome (or any web browser) on the Android phone.
3. Type the following exact address into the URL bar and press Enter:
   ```
   http://lumina.hub:8000/files/EduMesh.apk
   ```
4. The phone will download the APK file. Open it and click "Install" (You may need to allow "Install from Unknown Sources" in Android Settings).

**How to Use the App:**
1. Open the EduMesh app.
2. Wait for the Connection Gatekeeper to turn **Green** (`🟢 Hub Connected`), indicating the phone has found the offline network.
3. Type in your name to register. (The Hub will remember your unique ID forever).
4. Browse the available resources and click "Download" to save Textbooks and Videos directly to your phone.
5. Even if you walk away from the Wi-Fi network, you can still read and watch all downloaded materials. The next time you reconnect to the Hub, the app will automatically sync your offline reading activity to the Teacher Dashboard!
