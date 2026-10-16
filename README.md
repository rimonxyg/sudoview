# SudoView

A secure, lightweight, view-only screen sharing application for Android powered by **Flutter** and **WebRTC**, orchestrated by a minimal **Node.js WebSocket signaling server**.

Designed with a **cybersecurity-first** approach: explicit user consent, ephemeral single-use session codes, brute-force mitigation, and end-to-end encrypted peer-to-peer video streams.

---

## Architecture Overview

```
+-----------------------------------------------------------------+
|                       Node.js Signaling Server                  |
|                      (WebSocket on port 8082)                   |
+-----------------------------------------------------------------+
             ^                                      ^
             | JSON Signaling (create, join,        | JSON Signaling (join,
             |   offer, answer, ice, end)           |   answer, ice, end)
             v                                      v
+--------------------------+          +---------------------------+
|     Host (Android)       |          |     Viewer (Android)      |
|  - Shares screen         |          |  - Views remote screen    |
|  - Explicit consent      |          |  - Enters 6-digit code    |
|  - Visible STOP button   |          |  - Read-only stream       |
+--------------------------+          +---------------------------+
             |                                      ^
             +========= Direct WebRTC Stream =======+
                 (DTLS-SRTP Encrypted Video only)
```

1. **Signaling Only:** The server coordinates room rendezvous, SDP offer/answer exchange, and ICE candidates. Video media **never** passes through the server.
2. **Peer-to-Peer:** Video frames travel directly between devices over WebRTC encrypted with DTLS-SRTP.

---

## Security-First Design

* **Explicit Host Consent:** Screen sharing cannot start automatically. The Host must tap "Share my screen" and approve an explicit incoming connection dialog ("Allow connection from Viewer?") before the stream begins.
* **OS-Level Transparency:** Android's native MediaProjection capture consent dialog and the persistent system screen-capture notification remain visible at all times.
* **Prominent Stop Control:** A visible "Stop Sharing" button is displayed on the Host device at all times while active.
* **Ephemeral Session Codes:** Rooms are identified by a cryptographically random 6-digit numeric code (`crypto.randomInt`).
* **Session Timeout:** Unused rooms expire and are deleted automatically after 5 minutes.
* **Brute-Force Protection:** Any client sending 5 incorrect codes is immediately rate-limited with `too_many_attempts` and disconnected.
* **Single-Use Rooms:** Once a session ends or the Host disconnects, the room and its code are permanently purged.
* **No Remote Control:** The MVP is strictly view-only. No input injection, touch simulation, or accessibility abuse.

---

## Repository Structure

```
sudoview/
├── server/                 # Node.js WebSocket signaling server
│   ├── package.json        # Dependencies (ws only)
│   ├── server.js           # Server logic (rooms, rate-limits, relay)
│   └── test.js             # Automated test suite (8 checks)
├── app/                    # Flutter Android application
│   ├── pubspec.yaml        # flutter_webrtc, web_socket_channel, shared_preferences
│   ├── android/            # Native Android Gradle configuration
│   └── lib/                # Flutter source code
└── README.md
```

---

## Getting Started

### Prerequisites

* **Node.js**: v18+ LTS
* **Flutter**: 3.47+ (stable channel)
* **Android SDK**: API 34+ with command-line tools & OpenJDK 21

---

### 1. Running the Signaling Server

```bash
cd server
npm install
npm start
```

By default, the server listens on port **8082** (or `PORT` environment variable).

#### Running Server Automated Tests:

```bash
cd server
npm test
```

Verifies all 8 core signaling features:
1. Room creation with 6-digit code
2. Rejection of invalid codes (`invalid_code`)
3. Join request and waiting state coordination
4. Host acceptance (`accepted`)
5. SDP Offer relay
6. SDP Answer relay
7. Session termination (`ended` & room purge)
8. Rate-limiting lockout after 5 failed attempts (`too_many_attempts`)

---

### 2. Building & Running the Flutter App

Ensure your Android device has **USB debugging enabled** and is connected to the same local Wi-Fi network as your signaling server machine.

```bash
cd app
flutter pub get
flutter run
```

To build a standalone debug APK:

```bash
cd app
flutter build apk --debug
```

The compiled APK will be located at:
`app/build/app/outputs/flutter-apk/app-debug.apk`

---

## Signaling Protocol

All signaling messages are JSON objects transferred over WebSocket.

| Type | Direction | Payload | Description |
|---|---|---|---|
| `create` | Host -> Server | None | Requests a new session room |
| `created` | Server -> Host | `code` (6 digits) | Returns the generated room code |
| `join` | Viewer -> Server | `code` (6 digits) | Requests to join an active room |
| `join-request` | Server -> Host | None | Informs host of an incoming viewer |
| `waiting` | Server -> Viewer | None | Informs viewer waiting for host decision |
| `accept` | Host -> Server | None | Host accepts the viewer connection |
| `accepted` | Server -> Viewer | None | Informs viewer that host accepted |
| `decline` | Host -> Server | None | Host rejects the viewer connection |
| `declined` | Server -> Viewer | None | Informs viewer that host declined |
| `offer` | Host <-> Server <-> Viewer | `sdp` (string) | WebRTC SDP offer relayed |
| `answer` | Viewer <-> Server <-> Host | `sdp` (string) | WebRTC SDP answer relayed |
| `ice` | Host <-> Server <-> Viewer | `candidate` (object) | ICE candidate relayed |
| `end` | Either -> Server | None | Ends session and notifies other peer |
| `peer-left` | Server -> Client | None | Sent if a peer disconnects unexpectedly |
| `error` | Server -> Client | `message` (string) | `invalid_code`, `room_busy`, `bad_message`, `too_many_attempts`, `not_allowed` |

---

## Network Notes

* Both devices and the server should be on the same local Wi-Fi network.
* Find your server machine's local IP address (`ip a` on Linux or `ipconfig` on Windows).
* In the app settings, set the signaling server URL to `ws://<SERVER_LAN_IP>:8082`.
* DTLS-SRTP WebRTC traffic uses STUN (`stun:stun.l.google.com:19302`) for peer discovery.

---

## License

This project is open-source under the [MIT License](LICENSE).
