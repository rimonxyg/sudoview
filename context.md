# TeachView: Project Context

> READ THIS FILE FIRST at the start of EVERY session, then read `tasks.md`.
> This file is the single source of truth. If something here conflicts with your own idea, THIS FILE WINS.
> Only edit this file in section 10 (Decisions Log). Never change sections 1 to 9 unless the user tells you to.

---

## 1. What we are building

A Flutter **Android** app plus a tiny **Node.js signaling server**.

- A person (the **Host**) shares their phone screen with another person (the **Viewer**) using a **6-digit code**.
- MVP is **view-only**: the Viewer sees the Host's screen live. No remote control.
- Purpose: help or teach someone remotely (like a very small AnyDesk / TeamViewer QuickSupport).
- It is an internship project with a **cybersecurity focus**: explicit consent, encryption, expiring codes, brute-force protection.

App name: **TeachView** (can be renamed later by the user).

---

## 2. Hard rules (security and ethics). NEVER break these

1. The Host must always start sharing manually by tapping a button in the app.
2. The Viewer can only watch after the Host taps **Accept** on a dialog.
3. Android's own "start capturing" system dialog and the persistent notification must stay visible. Never hide or bypass them.
4. A visible **Stop** button must always be on the Host screen while sharing.
5. The code is 6 digits, single use, expires after 5 minutes if unused, and is deleted when the session ends.
6. No hidden mode, no auto-start, no sharing in the background after Stop.
7. No remote control (taps, keyboard) in the MVP.
8. Video travels only over WebRTC (encrypted with DTLS-SRTP). Never send video through the server.
9. Never commit secrets (`.env`, keystores, `key.properties`, `local.properties`).

---

## 3. Tech stack (FIXED. Do not substitute or add anything else without asking the user)

**App** (`app/`)
- Flutter stable, Dart, Android only
- Packages: `flutter_webrtc`, `web_socket_channel`, `shared_preferences`
- Nothing else unless a task says so

**Server** (`server/`)
- Node.js LTS, plain JavaScript (no TypeScript, no Express)
- Package: `ws` only
- Built-in `http`, `crypto` modules are allowed

**Network**
- STUN: `stun:stun.l.google.com:19302`
- No TURN server in the MVP (known limitation: may fail on some strict networks)
- Server runs on the laptop. Phones join the same Wi-Fi. Server URL looks like `ws://<LAPTOP_LAN_IP>:8082`

---

## 4. Repo structure

```
teachview/
  context.md
  tasks.md
  README.md
  .gitignore
  server/
    package.json
    server.js
    test.js
  app/                      (Flutter project)
    lib/
      main.dart
      screens/
        home_screen.dart
        host_screen.dart
        viewer_screen.dart
      services/
        signaling.dart
        settings.dart
```

Do not create files outside this structure without a task telling you to.

---

## 5. Signaling protocol (EXACT. Do not rename or add message types)

All messages are JSON text over WebSocket. Every message has a `type` field.

### Client to Server

| type | fields | sent by |
|---|---|---|
| `create` | none | Host |
| `join` | `code` (string, 6 digits) | Viewer |
| `accept` | none | Host |
| `decline` | none | Host |
| `offer` | `sdp` (string) | Host |
| `answer` | `sdp` (string) | Viewer |
| `ice` | `candidate` (object with `candidate`, `sdpMid`, `sdpMLineIndex`) | both |
| `end` | none | both |

### Server to Client

| type | fields | sent to |
|---|---|---|
| `created` | `code` | Host |
| `join-request` | none | Host |
| `waiting` | none | Viewer |
| `accepted` | none | Viewer |
| `declined` | none | Viewer |
| `offer` / `answer` / `ice` | same fields as above, relayed unchanged | the other side |
| `peer-left` | none | the remaining side |
| `ended` | none | the other side |
| `error` | `message` (string) | sender |

### Error messages (the only allowed values)
`invalid_code`, `room_busy`, `bad_message`, `too_many_attempts`, `not_allowed`

### Session flow
1. Host sends `create`. Server replies `created` with a 6-digit code.
2. Viewer sends `join` with the code. Server replies `waiting` to Viewer and sends `join-request` to Host.
3. Host taps Accept and sends `accept`. Server sends `accepted` to Viewer.
   Host taps Decline and sends `decline`. Server sends `declined` to Viewer and the room goes back to waiting (viewer slot is empty).
4. After Accept, the Host starts screen capture, creates the WebRTC offer and sends `offer`.
5. Viewer replies with `answer`. Both sides exchange `ice` messages until connected.
6. Either side sends `end` (or disconnects). The other side gets `ended` (or `peer-left`). The room is deleted.

### Server room rules
- One room = one Host + at most one Viewer.
- Room is deleted after 5 minutes if no session started, and when the Host leaves.
- A connection that sends 5 wrong codes gets `too_many_attempts` and is closed.
- Server only relays messages. It never stores or touches video.

---

## 6. Environment notes

- Test screen sharing on a **real Android phone with USB debugging**. Emulators are unreliable for screen capture.
- The Viewer can run on a second phone or on an emulator.
- Android blocks plain `ws://` traffic by default. For development only, the manifest needs `android:usesCleartextTraffic="true"` (task T2.7). Mention in the README that production should use `wss://`.
- Phones and laptop must be on the same Wi-Fi. Find the laptop IP with `ipconfig` (Windows) or `ip a` (Linux). Allow port 8082 through the laptop firewall if the phone cannot connect.

---

## 7. Rules for the AI agent (Antigravity). Follow strictly

1. **Start of every session:** read `context.md`, then `tasks.md`. Run `git status` and `git log --oneline -5`. Continue from the `CURRENT TASK` line in `tasks.md`.
2. **One task at a time.** Never start the next task before the current one is verified, ticked, committed and pushed.
3. **Never skip, reorder, merge or invent tasks.** Never add features that are not in a task.
4. **Do not guess APIs.** If you are not 100% sure how a package works, open its README on pub.dev or read its source in the pub cache. Follow the README exactly. Do not invent method names.
5. **Verify with a real command.** Every task has a "Done when" check. Run it and read the output. Do not assume it passed.
6. **If something fails:** try to fix it at most 3 times. After the third failure, write the full error into the Progress Log with status `BLOCKED` and STOP. Tell the user. Do not work around it by changing the stack or protocol.
7. **Do not change versions, the stack, the protocol, or the folder structure.**
8. **Keep code simple and commented.** Short files, clear names, no clever tricks. This is a learning and demo project.
9. **After every finished task**, do all of this in order:
   1. Tick the box in `tasks.md`.
   2. Update the `CURRENT TASK` line to the next task.
   3. Add one line to the Progress Log in `tasks.md`.
   4. `git add -A`
   5. `git commit -m "<TaskID>: <short description>"`
   6. `git push`
10. If power or internet was lost mid-task: run `git status` and `git diff`, check what is half done, finish that same task, and only then continue.
11. Ask the user only when a task says to, or when you are BLOCKED.
12. **Persistent project settings:** Repo name is SudoView (`https://github.com/rimonxyg/sudoview.git`) and default signaling port is `8082` (due to local Docker port conflicts on 8080 and 8081 reserved by user). Never forget or revert these choices across sessions and restarts.

---

## 8. MVP definition of done

- Server passes `npm test`.
- Host phone shows a 6-digit code. Viewer phone enters it. Host sees an Accept/Decline dialog.
- After Accept, Viewer sees the Host screen live.
- Host can press Stop and the Viewer returns to the home screen with a message.
- Wrong or expired codes show a clear error.
- README explains setup and the security design.
- Everything is pushed to GitHub and tagged `v0.1.0`.

---

## 9. Out of scope for the MVP (do NOT build, do NOT suggest while building)

Remote control (taps/swipes), Accessibility Service, audio, file transfer, accounts/login, TURN server, iOS, web viewer, database.

---

## 10. Decisions Log (append only)

| Date | Decision | Reason |
|---|---|---|
| (start) | View-only MVP, 6-digit code, Accept/Decline, WebRTC, Node `ws` signaling | Simple, secure, demo-able |
| 2026-10-16 | Project/repo name is SudoView | User set repository to sudoview (`https://github.com/rimonxyg/sudoview.git`) |
| 2026-10-16 | Signaling server default port is 8082 | Port 8080 is occupied by OSCP Docker container and 8081 is reserved by user |
| 2026-10-17 | Repository visibility set to Private | Allows tracking context.md and tasks.md securely and enables GitHub Codespaces cloud dev |


