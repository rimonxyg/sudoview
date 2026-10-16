# TeachView: Tasks

> Read `context.md` first. Do ONE task at a time, in order. Never skip.
> After each task: tick the box, update CURRENT TASK, add a Progress Log line, then `git add -A`, `git commit`, `git push`.

**CURRENT TASK: T1.3**

**GITHUB_REPO_URL:** https://github.com/rimonxyg/sudoview.git

---

## PHASE 0: Setup

### [x] T0.1 Check tools
- Run: `flutter --version`, `flutter doctor`, `node -v`, `npm -v`, `git --version`
- Done when: all five print a version, and `flutter doctor` shows the Android toolchain as OK.
- If anything is missing: STOP and tell the user exactly what is missing. Do not install things on your own.
- Commit: none (nothing changed). Just tick the box and log it.

### [x] T0.2 Check the GitHub URL
- Look at GITHUB_REPO_URL above. If it still says "user fills this in", STOP and ask the user for the URL.
- Done when: the URL is filled in.
- Commit: none.

### [x] T0.3 Create repo skeleton and first push
- Create folders `server/` and `app/` (leave `app/` empty for now).
- Create `.gitignore` containing at least: `node_modules/`, `.env`, `build/`, `.dart_tool/`, `*.keystore`, `*.jks`, `key.properties`, `local.properties`, `.idea/`, `*.apk`.
- Create `README.md` with only the title "TeachView" and one line: "Work in progress."
- Run: `git init`, `git branch -M main`, `git remote add origin <GITHUB_REPO_URL>`.
- Done when: `git push -u origin main` succeeds and the files are visible on GitHub.
- Commit: `T0.3: repo skeleton`

---

## PHASE 1: Signaling server (`server/`)

### [x] T1.1 Init server project
- `cd server`, `npm init -y`, `npm install ws`.
- In `package.json` add scripts: `"start": "node server.js"` and `"test": "node test.js"`.
- Done when: `node -e "require('ws')"` runs with no error.
- Commit: `T1.1: init server`

### [x] T1.2 Basic WebSocket server
- Create `server/server.js`. Use Node's `http` to create a server and attach a `ws` WebSocketServer.
- Port: `process.env.PORT` or `8082`. Print `Server listening on <port>`.
- On each message: parse JSON. If parsing fails or `type` is missing, reply `{"type":"error","message":"bad_message"}`.
- Done when: `npm start` prints the listening line, and connecting with a WebSocket client and sending `{"type":"foo"}` returns the `bad_message` error. (Use a quick one-off node script to check, do not keep it.)
- Commit: `T1.2: basic ws server`

### [ ] T1.3 Rooms: create and join
- In `server.js` keep a `Map` called `rooms`: code → `{ host, viewer, createdAt }`.
- `create`: generate a 6-digit code with `crypto.randomInt(100000, 1000000)` as a string. Regenerate if it already exists. Store the room. Reply `created` with the code.
- `join`: if the code does not exist reply error `invalid_code`. If the room already has a viewer reply error `room_busy`. Otherwise set `viewer`, reply `waiting` to the viewer, and send `join-request` to the host.
- Done when: a one-off script shows host gets a code, viewer joins with it, host receives `join-request`, viewer receives `waiting`. A wrong code returns `invalid_code`.
- Commit: `T1.3: create and join`

### [ ] T1.4 Accept, decline, relay, end
- `accept` (host only): send `accepted` to the viewer.
- `decline` (host only): send `declined` to the viewer and set `room.viewer = null`.
- `offer`, `answer`, `ice`: forward the message unchanged to the other side of the room.
- `end`: send `ended` to the other side and delete the room.
- When any socket closes: if it was the host, send `peer-left` to the viewer and delete the room. If it was the viewer, send `peer-left` to the host and set `room.viewer = null`.
- If a client sends a message it is not allowed to send (for example a viewer sending `accept`), reply error `not_allowed`.
- Done when: a one-off script walks through accept, offer relay, end, and decline correctly.
- Commit: `T1.4: accept decline relay end`

### [ ] T1.5 Expiry and brute-force protection
- When a room is created, set a 5-minute timer. If no session has started (no accept happened), delete the room. Clear the timer when the room is deleted.
- Count wrong `join` codes per connection. On the 5th wrong code reply error `too_many_attempts` and close that connection.
- Done when: a one-off script confirms 5 wrong codes get the connection closed. (For the expiry check, temporarily set the timer to 3 seconds, test, then set it back to 5 minutes.)
- Commit: `T1.5: expiry and attempt limit`

### [ ] T1.6 Automated test
- Create `server/test.js` that starts the server on a test port (for example 8090), then runs these checks with the `ws` client and prints `PASS` or `FAIL` for each:
  1. create returns a 6-digit code
  2. wrong code returns `invalid_code`
  3. valid join gives host `join-request` and viewer `waiting`
  4. accept gives viewer `accepted`
  5. offer from host reaches viewer unchanged
  6. answer from viewer reaches host unchanged
  7. end gives the other side `ended`
  8. 5 wrong codes returns `too_many_attempts`
- The script must exit with code 0 only if all checks pass, and close the server when finished.
- Done when: `npm test` prints PASS for all 8 checks.
- Commit: `T1.6: server tests`

---

## PHASE 2: Flutter app skeleton (`app/`)

### [ ] T2.1 Create Flutter project
- From the repo root run: `flutter create --org com.teachview --project-name teachview --platforms android app`
- Done when: `cd app && flutter analyze` shows no errors.
- Commit: `T2.1: flutter project`

### [ ] T2.2 Add packages
- `cd app && flutter pub add flutter_webrtc web_socket_channel shared_preferences`
- Done when: `flutter pub get` succeeds and all three are listed in `pubspec.yaml`.
- Commit: `T2.2: add packages`

### [ ] T2.3 Android minimum SDK
- Open the `flutter_webrtc` README on pub.dev and find its Android requirements (minSdk and anything else mandatory).
- Apply exactly what it says in `app/android/app/build.gradle` (or `build.gradle.kts`).
- Done when: `flutter build apk --debug` succeeds.
- Commit: `T2.3: android sdk config`

### [ ] T2.4 Folders and home screen
- Create the files listed in `context.md` section 4 under `app/lib/`.
- `home_screen.dart`: two large buttons, "Share my screen" and "Watch a screen", and a settings icon in the app bar. The buttons open `HostScreen` and `ViewerScreen`, which for now only show a `Scaffold` with a title.
- `main.dart` shows `HomeScreen`. Use Material 3.
- Done when: `flutter analyze` is clean and the app launches on the phone showing both buttons.
- Commit: `T2.4: home screen`

### [ ] T2.5 Server URL setting
- `services/settings.dart`: two functions `getServerUrl()` and `setServerUrl(String)` using `shared_preferences`. Default value: `ws://192.168.0.100:8080`.
- The settings icon opens a dialog with a text field to edit the URL, and a Save button.
- Done when: after saving a URL and restarting the app, the dialog shows the saved URL.
- Commit: `T2.5: server url setting`

### [ ] T2.6 Signaling client
- `services/signaling.dart`: class `SignalingClient` with:
  - `Future<void> connect(String url)`
  - `void send(Map<String, dynamic> message)` (JSON encode)
  - `Stream<Map<String, dynamic>> get messages` (JSON decode)
  - `void close()`
- Use `web_socket_channel`. No UI code in this file.
- Done when: `flutter analyze` is clean.
- Commit: `T2.6: signaling client`

### [ ] T2.7 Manifest for network (development only)
- In `app/android/app/src/main/AndroidManifest.xml` add `<uses-permission android:name="android.permission.INTERNET"/>` if missing.
- On the `<application>` tag add `android:usesCleartextTraffic="true"` and put an XML comment above it: `DEV ONLY: use wss:// in production`.
- Done when: `flutter build apk --debug` succeeds.
- Commit: `T2.7: network manifest`

---

## PHASE 3: Host side (shares the screen)

### [ ] T3.1 Host screen: create session and show code
- On open: read the server URL, connect with `SignalingClient`, send `{"type":"create"}`.
- When `created` arrives show the code in a very large text with the label "Your code" and the text "Waiting for viewer...".
- Show a red **Stop** button that sends `end`, closes the socket and goes back.
- Show friendly text if the connection fails.
- Done when: with the server running (`npm start`) and the phone on the same Wi-Fi, the phone shows a 6-digit code that matches what the server created.
- Commit: `T3.1: host shows code`

### [ ] T3.2 Host: accept or decline dialog
- When `join-request` arrives show an AlertDialog: "Someone wants to view your screen." with buttons **Decline** and **Accept**. The dialog cannot be dismissed by tapping outside.
- Decline sends `{"type":"decline"}` and the screen goes back to "Waiting for viewer...".
- Accept sends `{"type":"accept"}` and moves to the next step (which does nothing yet except show "Starting..." text).
- Done when: using a one-off node script as the viewer, the dialog appears, and both buttons produce the right server messages.
- Commit: `T3.2: host accept decline`

### [ ] T3.3 Android permissions and foreground service for capture
- Open the `flutter_webrtc` README section about screen sharing on Android. Follow it exactly for: manifest permissions, the foreground service declaration (type `mediaProjection`), and any notification permission.
- Do not invent your own service. Use what the README says.
- Done when: `flutter build apk --debug` succeeds and the manifest contains what the README requires.
- Commit: `T3.3: capture permissions`

### [ ] T3.4 Host: start screen capture after Accept
- After the user taps Accept, request the screen stream using the method from the `flutter_webrtc` README (`getDisplayMedia`).
- Done when: after tapping Accept, Android shows its own "start capturing / casting" dialog, a persistent notification appears after confirming, and the app logs `capture started`. Cancelling the system dialog must send `end` and return to the home screen.
- Commit: `T3.4: start capture`

### [ ] T3.5 Host: WebRTC offer
- Create an `RTCPeerConnection` with iceServers `[{'urls': 'stun:stun.l.google.com:19302'}]`.
- Add the captured stream's tracks. Create the offer, `setLocalDescription`, send `{"type":"offer","sdp":...}`.
- Send every local ICE candidate as `{"type":"ice","candidate":{candidate, sdpMid, sdpMLineIndex}}`.
- Handle incoming `answer` (`setRemoteDescription`) and incoming `ice` (`addCandidate`).
- Done when: logs show offer sent, answer received, and ICE state reaching `connected` or `completed`. (Full check happens after Phase 4.)
- Commit: `T3.5: host webrtc`

### [ ] T3.6 Host: stop and cleanup
- The Stop button must: stop all stream tracks, close the peer connection, stop the screen-capture foreground service, send `end`, close the socket, and go back to the home screen.
- Also run the same cleanup when `peer-left` or `ended` arrives, or when the screen is closed.
- Done when: after Stop, the notification disappears and the status-bar casting icon is gone.
- Commit: `T3.6: host cleanup`

---

## PHASE 4: Viewer side (watches the screen)

### [ ] T4.1 Viewer screen: enter code and join
- Text field (numbers only, max 6 digits) and a **Join** button.
- On Join: connect, send `{"type":"join","code":...}`. Show states: "Waiting for host to accept...", "Host declined", and error text for `invalid_code`, `room_busy`, `too_many_attempts`.
- Done when: a wrong code shows a clear message, and a correct code makes the host phone show the Accept dialog.
- Commit: `T4.1: viewer join`

### [ ] T4.2 Viewer: WebRTC answer
- When the Join message is sent, create the `RTCPeerConnection` (same STUN setup) and an `RTCVideoRenderer` (call `initialize()`).
- On incoming `offer`: `setRemoteDescription`, `createAnswer`, `setLocalDescription`, send `{"type":"answer","sdp":...}`.
- Exchange `ice` messages both ways.
- On `onTrack`: set `renderer.srcObject` to the received stream.
- Done when: logs show offer received, answer sent, and a remote track received.
- Commit: `T4.2: viewer webrtc`

### [ ] T4.3 Viewer: show the video
- After the first remote track arrives show `RTCVideoView` full screen with `objectFit` contain on a black background.
- Add a small **Leave** button: sends `end`, disposes the renderer and peer connection, closes the socket, goes home.
- Done when: the viewer phone shows the host's screen live.
- Commit: `T4.3: viewer video`

### [ ] T4.4 Viewer: handle endings
- On `ended`, `peer-left` or connection loss: clean up, go to the home screen, and show a SnackBar "Session ended".
- Done when: pressing Stop on the host returns the viewer home with the message, and the reverse also works.
- Commit: `T4.4: viewer endings`

---

## PHASE 5: Polish and delivery

### [ ] T5.1 Full manual test (the USER does this, agent only prepares)
- Agent writes the checklist below into the Progress Log and asks the user to run it on two devices. The agent must STOP here until the user replies with the results.
  1. Server running, both devices on the same Wi-Fi.
  2. Host shows a code. Viewer with a wrong code gets an error.
  3. Viewer with the right code. Host sees Accept/Decline.
  4. Decline works. Join again and Accept works.
  5. Viewer sees the host screen live.
  6. Host Stop returns both to the home screen and removes the notification.
  7. Viewer Leave works and the host can start a new session.
  8. Code expires after 5 minutes unused.
- Fix any failure as a new sub-task `T5.1a`, `T5.1b` and so on, each committed separately.

### [ ] T5.2 Connection status indicator
- On both screens show a small status text from the peer connection state: Connecting, Connected, Disconnected.
- Done when: the status changes correctly during a session.
- Commit: `T5.2: connection status`

### [ ] T5.3 Session timer and auto-stop
- On the Host screen show how long the session has been running (mm:ss). Automatically stop the session after 30 minutes with a message.
- Done when: the timer counts up, and (after temporarily setting the limit to 1 minute and testing, then restoring 30) auto-stop works.
- Commit: `T5.3: session timer`

### [ ] T5.4 README
- Write `README.md` with: what the app does, how it works (short diagram in text), how to run the server, how to set the server URL in the app, how to build the APK, the **security design** (consent dialog, expiring one-time code, attempt limit, DTLS-SRTP, visible notification, Stop button), known limitations (no TURN, ws not wss in dev, view-only), and a roadmap (pointer overlay, remote control with Accessibility Service, TURN, wss).
- Done when: the README renders properly on GitHub.
- Commit: `T5.4: readme`

### [ ] T5.5 Final check and release
- Run `npm test` in `server/` and `flutter analyze` in `app/`. Both must be clean.
- Make sure `git status` is clean and `git push` is done.
- Create tag: `git tag v0.1.0` and `git push origin v0.1.0`.
- Done when: the tag is visible on GitHub.

---

## STRETCH (DO NOT START unless the user explicitly says so)

- S1: Pointer overlay (Viewer draws a dot the Host can see)
- S2: Remote control with an Android AccessibilityService
- S3: TURN server (coturn)
- S4: `wss://` with TLS

---

## PROGRESS LOG (append one line per finished or blocked task, newest at the bottom)

| Date and time | Task | Status | Note |
|---|---|---|---|
| 2026-10-16 11:58 | T0.1 | DONE | Flutter 3.47.7, Android toolchain OK, node v24.19.0, npm 12.0.2, git 2.53.0 |
| 2026-10-16 12:28 | T0.2 | DONE | GitHub repo https://github.com/rimonxyg/sudoview.git verified and set |
| 2026-10-16 12:29 | T0.3 | DONE | Repo skeleton created, initial push to GitHub main |
| 2026-10-16 12:30 | T1.1 | DONE | Server project initialized with ws package and scripts |
| 2026-10-16 14:35 | T1.2 | DONE | Basic WebSocket server implemented on port 8082, handling invalid messages |
