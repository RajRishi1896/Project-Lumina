# Project Lumina: Master Implementation Plan (MVP)

Project Lumina is a self-hosted, offline educational appliance designed for zero-bandwidth environments. It repurposes a Debian 12 server into a NAS that serves curated resources to a Flutter APK via a local mesh network.

## 1. Design Philosophy (Flat 2.0)
The visual identity is "Digital Scholar"—scholarly, crisp, and high-contrast. 

- **Aesthetic**: No blurs, gradients, or shadows. Tonal layering and crisp outlines only.
- **Colors**:
  - `Base Surface`: `#fdf7ff`
  - `Primary Deep Blue`: `#1A2B44`
  - `Academic Teal`: `#007083`
  - `Saffron (CTA)`: `#FFD300`
  - `Success Green`: `#38A169`
- **Typography**: Atkinson Hyperlegible Next.
  - Headers: Weight 800.
  - Body: Weight 400.
- **Interactions**: 
  - Transitions < 200ms.
  - Touch targets ≥ 48px.

---

## 2. Content & Resource Architecture
The app features specialized views for four resource types:

| Resource Type | UI Treatment | Technical Integration |
| :--- | :--- | :--- |
| **Kiwix (Wikipedia)** | "Launch Encyclopedia" Card | WebView to local ZIM server (`:8080`) |
| **Khan Academy** | Video Library | `video_player` / `chewie` (MP4) |
| **Textbooks** | PDF Library | `flutter_pdfview` |
| **PYQs** | Starred/High-Priority | PDF/Image viewer + Subject filtering |

---

## 3. Key Functional Requirements

### Local Discovery & Connectivity
- Communicate with Debian server via Local IP (e.g., `http://192.168.x.x`).
- Handle mesh network latency and connection drops gracefully.

### Persistence Module (Core Logic)
- **Download Manager**: Modular service using `Dio` and `path_provider`.
- **Storage**: Save files to `/LuminaResources` sub-folder.
- **"Offline First" Logic**:
  1. Check for local copy in `/LuminaResources`.
  2. If present: Stream/View from local storage.
  3. If absent: Stream from server and provide download option.
- **UI Feedback**:
  - `Offline Ready` indicator: Success Green (#38A169) status pill.
  - `Progress Bars`: Academic Teal solid-fill.

---

## 4. Proposed Implementation Steps

### Step 1: Foundation & Theme Configuration [NEW]
- [ ] Initialize Flutter project and `pubspec.yaml`.
- [ ] Implement `LuminaTheme` mapping all hex codes and Atkinson font weights.
- [ ] Create core `LuminaComponents` (Buttons, Cards, Progress Bars).

### Step 2: Login & Identity Page [NEW]
- [ ] Build the "Digital Scholar" login interface.
- [ ] Implement session persistence for offline use.

### Step 3: 4-Quadrant Dashboard [NEW]
- [ ] Build the Home Page layout for the four resource categories.
- [ ] Implement responsive grid (Mobile vs Tablet).

### Step 4: Specialized Resource Views [NEW]
- [ ] **Kiwix**: WebView integration.
- [ ] **Khan Academy**: Video player with 200ms transitions.
- [ ] **Library (Textbooks/PYQs)**: PDF/Image viewers.

### Step 5: Persistence & Download Service [NEW]
- [ ] Implement modular Download Service with `Dio`.
- [ ] Setup "Check Local First" logic.
- [ ] Integrate "Offline Ready" status pills.

---

## 5. Verification Plan

### Automated Tests
- Unit tests for the Persistence Logic (Local vs Remote check).
- Widget tests for 48px touch target compliance.

### Manual Verification
- Visual audit against Flat 2.0 (no blurs/shadows).
- Connectivity test with a local mock server.
