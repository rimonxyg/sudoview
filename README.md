# SudoView

A secure, lightweight, view-only screen sharing application for Android powered by **Flutter** and **WebRTC**, orchestrated by a minimal **Node.js WebSocket signaling server**.

Designed with a **cybersecurity-first** architecture: explicit user consent, ephemeral single-use session codes, brute-force mitigation, visible OS indicators, automated session safety timeouts, and end-to-end encrypted peer-to-peer video streaming.

---

## What SudoView Does

SudoView enables a **Host** to securely share their Android device's screen with a **Viewer** using a 6-digit one-time code.
- **View-Only MVP:** The Viewer watches the Host screen in real time with high performance and low latency.
- **Rendezvous by Code:** No user accounts, passwords, or persistent profiles required.
- **Use Cases:** Remote tech support, teaching family members how to navigate settings, or demonstrating app workflows remotely.

---

## How It Works

```
+-----------------------------------------------------------------+
|                    Node.js Signaling Server                     |
|                    (WebSocket on port 8082)                     |
+-----------------------------------------------------------------+
             ^                                      ^
             | JSON Signaling (create, join,        | JSON Signaling (join,
             |   offer, answer, ice, end)           |   answer, ice, end)
             v                                      v
+--------------------------+          +---------------------------+
|      Host (Android)      |          |     Viewer (Android/Web)  |
|  - Generates 6-digit code|          |  - Enters 6-digit code    |
|  - Explicit Accept dialog|          |  - Direct video renderer  |
|  - MediaProjection stream|          |  - Fullscreen display     |
|  - Live timer & STOP btn |          |  - Instant Leave button   |
+--------------------------+          +---------------------------+
             |                                      ^
             +========= Direct WebRTC Stream =======+
                 (DTLS-SRTP Encrypted Video only)
```

1. **Signaling Server (Rendezvous):** The lightweight server handles room management, relays SDP offer/answer messages, and exchanges ICE candidates. Video frames **never** pass through or touch the server.
2. **Peer-to-Peer Video (WebRTC):** Once signaling completes, video flows directly between the two devices encrypted end-to-end with **DTLS-SRTP**.
3. **STUN Discovery:** Peer connections discover external network paths using Google's public STUN server (`stun:stun.l.google.com:19302`).

---

## Security-First Design

Security and user consent are built into every level of SudoView:

1. **Explicit Host Consent:** Screen sharing cannot start automatically or in the background. When a Viewer enters the code, a non-dismissible dialog (*"Someone wants to view your screen"*) appears on the Host phone with **Accept** and **Decline** options.
2. **OS-Level Transparency:** Android's native `MediaProjection` system prompt and persistent foreground service notification (`MediaProjectionService`) remain visible throughout the session. Never bypassed or hidden.
3. **Prominent Stop Button:** A persistent, red **Stop** button is always accessible on the Host screen while sharing is active.
4. **Active Session Timer & 30-Minute Auto-Stop:** The Host screen displays an active duration timer (`mm:ss`). To prevent accidental prolonged exposure, the app automatically terminates sharing and disconnects after **30 minutes**.
5. **Connection Status Indicators:** Both Host and Viewer screens display a live WebRTC connection status indicator (*Connecting*, *Connected*, *Disconnected*).
6. **Ephemeral One-Time Codes:** Rooms are identified by a cryptographically secure 6-digit numeric code (`crypto.randomInt`).
7. **5-Minute Code Expiry:** Codes expire and rooms are automatically purged after 5 minutes if no session starts.
8. **Brute-Force Rate Limiting:** Any connection that submits 5 invalid codes receives a `too_many_attempts` error and is immediately terminated by the server.
9. **Single-Use Rooms & Immediate Purge:** Once a session ends or either peer disconnects, the room and its code are permanently deleted from memory.
10. **Strictly View-Only:** No remote control, touch injection, or accessibility service abuse in the MVP.

---

## Repository Structure

```
sudoview/
├── server/                     # Node.js WebSocket signaling server
│   ├── package.json            # Dependencies ('ws' only)
│   ├── server.js               # Signaling logic (rooms, expiry, rate limits)
│   └── test.js                 # Automated test suite (8 checks)
├── app/                        # Flutter Android & Web application
│   ├── android/                # Native Android config & MediaProjection service
│   ├── lib/
│   │   ├── main.dart           # App entry point (Material 3)
│   │   ├── screens/
│   │   │   ├── home_screen.dart    # Role selector & Settings access
│   │   │   ├── host_screen.dart    # Host code generation, consent, stream & timer
│   │   │   └── viewer_screen.dart  # Viewer code input & WebRTC video renderer
│   │   └── services/
│   │       ├── signaling.dart      # WebSocket signaling client
│   │       └── settings.dart       # Server URL persistence (shared_preferences)
│   └── test/                   # Comprehensive Flutter unit & widget tests (21 tests)
├── .github/workflows/
│   └── build-apk.yml           # Automated Cloud CI APK build workflow
├── context.md                  # Project rules and single source of truth
├── tasks.md                    # Task checklist and progress log
└── README.md
```

---

## Getting Started

### Prerequisites

* **Node.js**: v18+ LTS
* **Flutter**: 3.44+ stable channel
* **Git**

---

### 1. Running the Signaling Server

```bash
cd server
npm install
npm start
```

By default, the server listens on port **8082** (customizable via the `PORT` environment variable).

#### Running Signaling Server Automated Tests:

```bash
cd server
npm test
```

All 8 automated checks verify:
1. Room creation with 6-digit code
2. Rejection of invalid codes (`invalid_code`)
3. Join request and waiting state coordination
4. Host acceptance (`accepted`)
5. SDP Offer relay
6. SDP Answer relay
7. Session termination (`ended` & room deletion)
8. 5-attempt rate-limiting lockout (`too_many_attempts`)

---

### 2. Setting the Server URL in the App

1. Launch **TeachView / SudoView** on your device.
2. Tap the ⚙️ **Settings icon** in the top right of the home screen AppBar.
3. Enter your server's WebSocket URL:
   - **Local Wi-Fi:** `ws://<LAPTOP_LAN_IP>:8082` (e.g. `ws://192.168.1.100:8082`)
   - **Cloud / Codespaces:** `wss://<FORWARDED_DOMAIN>:8082`
4. Tap **Save**. The URL is persisted across app restarts via `shared_preferences`.

> **Note:** The app automatically normalizes URLs (e.g., converts `http://` to `ws://` and `https://` to `wss://` and strips trailing slashes).

---

### 3. Building the Android APK

#### Option A: Automated Cloud CI (Recommended)
This repository includes a GitHub Actions workflow ([.github/workflows/build-apk.yml](.github/workflows/build-apk.yml)).
- Every push to `main` automatically triggers a cloud build on a 16GB runner.
- Download the ready-to-install APK from **GitHub → Actions → Latest run → Artifacts (`app-debug.zip`)**.
- No local Android SDK or Gradle compilation required!

#### Option B: Local Android Build (if Android SDK is installed)
```bash
cd app
flutter pub get
flutter build apk --debug
```
The compiled APK is placed at `app/build/app/outputs/flutter-apk/app-debug.apk`.

---

### 4. Running the Flutter Test Suite

```bash
cd app
flutter analyze
flutter test
```

Includes 21 automated unit and widget tests covering:
- Settings persistence and URL normalization
- WebSocket signaling serialization and streams
- Host consent dialog, offer creation, and ICE candidate exchange
- Viewer code validation, answer creation, and remote track handling
- WebRTC connection status state transitions
- Session duration timer count-up and 30-minute auto-stop
- Graceful session teardown and notification cleanup

---

## Signaling Protocol Reference

All signaling messages are JSON text over WebSocket.

| Type | Direction | Fields | Description |
|---|---|---|---|
| `create` | Host -> Server | None | Requests room creation |
| `created` | Server -> Host | `code` (6 digits) | Returns generated room code |
| `join` | Viewer -> Server | `code` (6 digits) | Requests to join room |
| `join-request` | Server -> Host | None | Prompts Host consent dialog |
| `waiting` | Server -> Viewer | None | Informs Viewer Host is deciding |
| `accept` | Host -> Server | None | Host accepts Viewer request |
| `accepted` | Server -> Viewer | None | Informs Viewer of acceptance |
| `decline` | Host -> Server | None | Host declines Viewer request |
| `declined` | Server -> Viewer | None | Informs Viewer of decline |
| `offer` | Host <-> Server <-> Viewer | `sdp` (string) | WebRTC SDP offer |
| `answer` | Viewer <-> Server <-> Host | `sdp` (string) | WebRTC SDP answer |
| `ice` | Host <-> Server <-> Viewer | `candidate` (object) | ICE candidate |
| `end` | Either -> Server | None | Cleanly ends session |
| `peer-left` | Server -> Other side | None | Sent if peer disconnects unexpectedly |
| `error` | Server -> Client | `message` (string) | `invalid_code`, `room_busy`, `bad_message`, `too_many_attempts`, `not_allowed` |

---

## Known Limitations (MVP)

* **No TURN Relay Server:** STUN (`stun:stun.l.google.com:19302`) handles direct NAT traversal. Networks behind strict symmetric NATs or restrictive corporate firewalls may fail to establish direct P2P connections without a TURN relay.
* **Cleartext `ws://` in Dev:** Development uses plain WebSocket (`ws://`). Android manifest includes `android:usesCleartextTraffic="true"` for local IP testing. Production should deploy `wss://` with TLS.
* **View-Only:** No remote touch, keyboard injection, or input interaction.

---

## Roadmap

- [ ] **S1: Pointer Overlay:** Viewer draws on screen to highlight areas for the Host.
- [ ] **S2: Remote Control:** Touch and swipe input injection using an Android `AccessibilityService`.
- [ ] **S3: TURN Server:** Integrated Coturn setup for reliable traversal across symmetric enterprise NATs.
- [ ] **S4: Production WSS / TLS:** Automatic TLS termination with Let's Encrypt / reverse proxy.

---

## License

This project is open-source under the [MIT License](LICENSE).
