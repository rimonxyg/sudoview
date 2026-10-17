# TeachView (SudoView) — Daily Catch-Up & Handoff Guide

> **Date**: October 17, 2026  
> **Repository**: [https://github.com/rimonxyg/sudoview](https://github.com/rimonxyg/sudoview) (Private)  
> **Current Branch**: `main`  
> **Current Task**: `T5.1` (Full Manual Test Verification)

---

## 1. What We Accomplished Today

Today we built and verified all core Host and Viewer screen sharing functionality across Phases 2, 3, and 4:

### A. Host Side (Phase 3)
- **Room Creation**: Host taps "Share my screen" -> Signaling server generates a 6-digit one-time code -> Code displays with active waiting spinner.
- **Security Consent Dialog**: When a Viewer enters the code, the Host sees a **non-dismissible modal dialog** (*"Someone wants to view your screen"*).
- **System Screen Capture**: Tapping **Accept** prompts the native Android MediaProjection permission dialog and launches our native Android foreground service (`MediaProjectionService.kt`) with an active OS notification.
- **WebRTC Offer & ICE**: Captured screen stream tracks are attached to an `RTCPeerConnection` (`stun:stun.l.google.com:19302`), generating the SDP offer and relaying ICE candidates.
- **Full Host Cleanup**: Tapping **Stop** or receiving `peer-left`/`ended` stops all media tracks, terminates the foreground service notification, closes the WebRTC peer connection, notifies the server (`{"type":"end"}`), and resets the UI cleanly.

### B. Viewer Side (Phase 4)
- **Code Input & Join**: Viewer enters 6 digits and taps **Join**. Handles waiting, decline, invalid code, room busy, and rate-limit lockout states.
- **WebRTC Answer**: On receiving the Host's offer, Viewer sets remote description, generates an SDP answer, relays local ICE candidates, and receives the remote video track.
- **Live Video Playback**: Automatically transitions into a full-screen `RTCVideoView` (`contain` fit on black background) with a floating **Leave** button.
- **Graceful Termination**: When session ends or Host leaves, cleans up peer connection and returns to home screen with a SnackBar (*"Session ended"*).

### C. Cloud-First CI & Infrastructure
- **Automated GitHub Actions CI** (`.github/workflows/build-apk.yml`):
  - Every git push automatically triggers a GitHub Actions runner (Ubuntu VM with 16GB RAM) that compiles `app-debug.apk` and uploads it to GitHub Actions Artifacts.
  - **No local heavy builds needed!** Protects your physical laptop hardware from thermal throttling and RAM saturation.
- **Codespace Container Memory Tuning**:
  - Configured `app/android/gradle.properties` with `-Xmx1536m -XX:MaxMetaspaceSize=384m`, single worker, and daemon disabled. Prevents the Linux kernel Out-Of-Memory (OOM) killer from terminating Gradle builds inside container environments.
- **Flutter Web Viewer**:
  - Enabled web platform (`app/web`) so you can open the Viewer directly in a desktop browser tab without needing a second physical Android phone.
- **URL Auto-Normalization**:
  - Implemented automatic URL normalization in `SignalingClient` & `Settings` dialog. Automatically transforms `https://` -> `wss://`, `http://` -> `ws://`, and cleans trailing slashes so copy-pasting URLs never fails with schema errors.

---

## 2. GitHub & Cloud Setup (What You Need to Know)

### Downloading the Android APK
You do **not** need to compile the APK on your laptop:
1. Open [https://github.com/rimonxyg/sudoview/actions](https://github.com/rimonxyg/sudoview/actions).
2. Click on the latest run titled **"Build Android APK"**.
3. Scroll down to the **Artifacts** section at the bottom.
4. Download `app-debug.zip`, extract `app-debug.apk`, and install it onto your Android phone.

### GitHub Codespaces Setup (if using Codespaces)
- **Codespace Domain**: `jubilant-train-x54gq7vjrvrpf67vx.github.dev`
- **Signaling Port**: `8082`
  - ⚠️ **CRITICAL GOTCHA**: Codespaces sets forwarded ports to *Private* by default. If port 8082 is Private, external phones cannot connect. In the Codespaces **Ports** tab, right-click Port 8082 -> **Port Visibility** -> change to **Public**.
  - WebSocket URL for App Settings: `wss://jubilant-train-x54gq7vjrvrpf67vx-8082.app.github.dev`
- **Web App Port**: `8085`
  - Web Viewer URL: `https://jubilant-train-x54gq7vjrvrpf67vx-8085.app.github.dev`

---

## 3. Command Cheatsheet for Tomorrow

### A. Running the Signaling Server
Choose either Local LAN or Cloud Codespaces:

#### Option 1: Local LAN (Both devices on same Wi-Fi)
```bash
# In your local terminal on this PC:
cd /home/ghost/Files/sohub_app/server
node server.js
# Your laptop IP is 192.168.0.148
# App Settings URL: ws://192.168.0.148:8082
```

#### Option 2: Cloud Codespaces
```bash
# In your Codespaces terminal:
cd /workspaces/sudoview/server
nohup npm start > /dev/null 2>&1 &
# Ensure Port 8082 is set to PUBLIC in the Ports tab!
```

---

### B. Running the Web Viewer in Browser (Desktop)
```bash
# Build the Flutter web app:
cd /home/ghost/Files/sohub_app/app
flutter build web

# Serve it on port 8085:
nohup python3 -m http.server 8085 --directory build/web > /dev/null 2>&1 &

# Open in Chrome / Firefox:
# Local: http://localhost:8085
# Codespaces: https://jubilant-train-x54gq7vjrvrpf67vx-8085.app.github.dev
```

---

### C. Running Automated Verification Tests
```bash
# 1. Signaling server unit tests (8 checks):
cd /home/ghost/Files/sohub_app/server
npm test

# 2. Flutter static analysis & unit/widget tests (17 tests):
cd /home/ghost/Files/sohub_app/app
flutter analyze
flutter test
```

---

### D. Git Sync
```bash
cd /home/ghost/Files/sohub_app
git status
git pull origin main
git log -n 5 --oneline
```

---

## 4. Step-by-Step Testing Guide for Tomorrow

### Scenario: Android Phone (Host) ➡️ Desktop Browser Tab (Viewer)

1. **Start Signaling Server**:
   ```bash
   cd /home/ghost/Files/sohub_app/server && node server.js
   ```
2. **Launch Web Viewer**:
   - Open Chrome to `http://localhost:8085` (or Codespaces web URL).
   - Click the ⚙️ **Gear icon** (top right) -> Enter Server URL: `ws://192.168.0.148:8082` -> Tap **Save**.
3. **Launch TeachView on Android Phone**:
   - Tap ⚙️ **Gear icon** -> Enter Server URL: `ws://192.168.0.148:8082` -> Tap **Save**.
   - Tap **"Share my screen"** -> A 6-digit code will appear (e.g. `482910`).
4. **Connect as Viewer**:
   - In browser tab, tap **"Watch a screen"**.
   - Type the 6-digit code and tap **Join**.
5. **Accept on Phone**:
   - Phone will show dialog: *"Someone wants to view your screen. Accept / Decline"*.
   - Tap **Accept**.
   - Android will ask for Screen Capture permission -> Tap **Start now**.
6. **Verify Live Stream**:
   - Browser will display the live phone screen full-width on a black background!
7. **Test Termination**:
   - Tap **Stop** on the phone -> Browser returns to home screen with *"Session ended"* SnackBar, and the Android persistent notification vanishes.

---

## 5. Important Gotchas to Keep in Mind

1. **Browser Address Bar vs App Settings**:
   - Never type `ws://192.168.0.148:8082` into Chrome's top address bar! Chrome will throw `ERR_UNKNOWN_URL_SCHEME`.
   - Browser address bars only accept `http://` or `https://`.
   - WebSocket URLs belong exclusively inside the **TeachView Settings (⚙️ icon)**.
2. **Never Run `flutter build apk` Locally**:
   - Per project instructions, the local machine is reserved for fast editing, `flutter analyze`, and `flutter test`.
   - All Android APK builds are performed automatically in GitHub Actions.
3. **Codespaces Port 8082 Visibility**:
   - If using Codespaces and the phone app says *"Connection refused"* or *"Unable to connect"*, check the **Ports** tab in Codespaces and make sure Port 8082 is **Public** (not Private).

---

## 6. Tomorrow's Next Steps (Phase 5)

Once you verify the live stream on test devices tomorrow:
- **T5.1**: Finish manual test checklist verification.
- **T5.2**: Add WebRTC connection status indicator (*Connecting, Connected, Disconnected*).
- **T5.3**: Add Host session duration timer (`mm:ss`) with automatic 30-minute safety timeout.
- **T5.4**: Write comprehensive `README.md` covering architecture, security design, and cloud workflows.
- **T5.5**: Run final clean tests (`npm test`, `flutter analyze`) and tag release `v0.1.0`.

Rest up, and we'll cross the finish line tomorrow! 🚀
