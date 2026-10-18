# SudoView - System Context & Diagnosis for Claude

## 1. Project Overview & Architecture
SudoView is a lightweight, view-only Android screen sharing application.
- **Host**: Android device running Flutter. Captures screen using `flutter_webrtc` (MediaProjection) and sends WebRTC video stream.
- **Viewer**: Web browser (or another Flutter app) connecting via WebRTC to view the live screen.
- **Signaling Server**: Node.js HTTP + WebSocket (`ws`) server running on port 8082. Manages 6-digit room codes, exchange of SDP offers/answers and ICE candidates.
- **GitHub Repository**: https://github.com/rimonxyg/sudoview

---

## 2. Current State & The Problem
1. **Status**:
   - All tests pass: 8/8 npm signaling tests, 21/21 Flutter widget/unit tests, 0 analysis errors.
   - GitHub Actions CI workflow built `app-debug.apk` successfully.
   - User installed the APK on a physical Android phone.
   - Signaling server is running on the host machine (`node server.js` on port 8082).
   - Web viewer is served on port 8085.

2. **The Problem ("The Infinite Circling Loop")**:
   - When the user opens the APK on their Android phone and taps "Start Sharing" or "Join Session", the app gets stuck forever on:
     `Connecting to signaling server...` with a spinning progress circle.
   - It never connects, never times out, and never shows an error.

3. **Root Cause Analysis**:
   - **Local Network Routing Barrier**:
     - The PC running `node server.js` is connected via Ethernet cable to Router 1 (`192.168.1.100`).
     - The physical Android phone is connected to Wi-Fi on Router 2 (`192.168.0.x`).
     - Because of double NAT / separate subnets, the phone cannot route packets to `ws://192.168.1.100:8082`.
   - **Localtunnel Failure**:
     - We tried exposing port 8082 using `npx localtunnel --port 8082` (`fuzzy-jars-knock.loca.lt`).
     - Localtunnel intercepts incoming requests with an anti-phishing HTML captcha splash screen (`"Click here to continue to fuzzy-jars-knock.loca.lt"`).
     - Because Flutter expects a WebSocket handshake (`101 Switching Protocols`) and receives an HTML page instead, `await channel.ready` hangs or fails silently.
   - **No Timeout in `signaling.dart`**:
     - In `app/lib/services/signaling.dart`, `connect()` runs `await channel.ready` with NO timeout. If the socket cannot be established or is waiting on a non-WS response, it hangs forever.

---

## 3. What We Need Solved
1. **Best Public Hosting / Tunnel for the Node.js Server**:
   - What is the most frictionless way to host or tunnel `server/server.js` with a public `wss://` endpoint that:
     - Has NO captcha or HTML interstitial pages (unlike localtunnel).
     - Works seamlessly with mobile Flutter `WebSocketChannel`.
     - Options: Cloudflare Tunnel / `cloudflared`, ngrok, Render (free web service), Glitch, Railway, or running phone on a shared Wi-Fi hotspot with the PC.
2. **Flutter Signaling Client Robustness**:
   - Update `app/lib/services/signaling.dart` to add a strict connection timeout (e.g. 10 seconds).
   - Proper error handling so that if the server is unreachable or rejects the connection, the UI immediately surfaces an error dialog instead of spinning indefinitely.

---

## 4. Key Source Code

### `server/server.js`
```javascript
const crypto = require('crypto');
const http = require('http');
const { WebSocketServer } = require('ws');

const port = process.env.PORT || 8082;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('TeachView Signaling Server\n');
});

const wss = new WebSocketServer({ server });
const rooms = new Map();

const CLEANUP_INTERVAL_MS = 30 * 1000;
const ROOM_TIMEOUT_MS = 5 * 60 * 1000;

function deleteRoom(code) {
  if (!code || !rooms.has(code)) return;
  const room = rooms.get(code);
  if (room.timer) {
    clearTimeout(room.timer);
    room.timer = null;
  }
  rooms.delete(code);
}

function sweepRooms(now = Date.now()) {
  for (const [code, room] of rooms.entries()) {
    if (!room.sessionStarted && now - room.createdAt > ROOM_TIMEOUT_MS) {
      if (room.host && room.host.readyState === room.host.OPEN) room.host.close();
      if (room.viewer && room.viewer.readyState === room.viewer.OPEN) room.viewer.close();
      deleteRoom(code);
    }
  }
}

let cleanupInterval = setInterval(() => sweepRooms(), CLEANUP_INTERVAL_MS);
if (cleanupInterval && cleanupInterval.unref) cleanupInterval.unref();

function sendError(ws, message) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify({ type: 'error', message }));
  }
}

function getRoomForClient(ws) {
  if (!ws.roomCode || !rooms.has(ws.roomCode)) return null;
  const room = rooms.get(ws.roomCode);
  if (room.host !== ws && room.viewer !== ws) return null;
  return room;
}

wss.on('connection', (ws) => {
  ws.failedAttempts = 0;

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw);
    } catch (err) {
      return sendError(ws, 'bad_message');
    }

    if (!data || typeof data !== 'object' || typeof data.type !== 'string') {
      return sendError(ws, 'bad_message');
    }

    switch (data.type) {
      case 'create': {
        let code;
        do {
          code = crypto.randomInt(100000, 1000000).toString();
        } while (rooms.has(code));

        const timer = setTimeout(() => {
          if (rooms.has(code)) {
            const r = rooms.get(code);
            if (!r.sessionStarted) {
              if (r.host && r.host.readyState === r.host.OPEN) r.host.close();
              if (r.viewer && r.viewer.readyState === r.viewer.OPEN) r.viewer.close();
              deleteRoom(code);
            }
          }
        }, ROOM_TIMEOUT_MS);
        if (timer.unref) timer.unref();

        rooms.set(code, {
          host: ws,
          viewer: null,
          createdAt: Date.now(),
          sessionStarted: false,
          timer
        });

        ws.roomCode = code;
        ws.role = 'host';
        ws.send(JSON.stringify({ type: 'created', code }));
        break;
      }

      case 'join': {
        const { code } = data;
        if (!code || typeof code !== 'string' || !rooms.has(code)) {
          ws.failedAttempts = (ws.failedAttempts || 0) + 1;
          if (ws.failedAttempts >= 5) {
            sendError(ws, 'too_many_attempts');
            ws.close();
            return;
          }
          return sendError(ws, 'invalid_code');
        }

        const room = rooms.get(code);
        if (room.viewer) {
          return sendError(ws, 'room_busy');
        }

        room.viewer = ws;
        ws.roomCode = code;
        ws.role = 'viewer';

        ws.send(JSON.stringify({ type: 'waiting' }));
        if (room.host && room.host.readyState === room.host.OPEN) {
          room.host.send(JSON.stringify({ type: 'join-request' }));
        }
        break;
      }

      case 'accept': {
        const room = getRoomForClient(ws);
        if (!room || ws !== room.host || !room.viewer) return sendError(ws, 'not_allowed');
        room.sessionStarted = true;
        if (room.timer) {
          clearTimeout(room.timer);
          room.timer = null;
        }
        if (room.viewer.readyState === room.viewer.OPEN) {
          room.viewer.send(JSON.stringify({ type: 'accepted' }));
        }
        break;
      }

      case 'decline': {
        const room = getRoomForClient(ws);
        if (!room || ws !== room.host) return sendError(ws, 'not_allowed');
        if (room.viewer) {
          if (room.viewer.readyState === room.viewer.OPEN) {
            room.viewer.send(JSON.stringify({ type: 'declined' }));
          }
          room.viewer.roomCode = null;
          room.viewer.role = null;
          room.viewer = null;
        }
        break;
      }

      case 'offer': {
        const room = getRoomForClient(ws);
        if (!room || ws !== room.host || typeof data.sdp !== 'string') return sendError(ws, 'not_allowed');
        room.sessionStarted = true;
        if (room.timer) {
          clearTimeout(room.timer);
          room.timer = null;
        }
        if (room.viewer && room.viewer.readyState === room.viewer.OPEN) {
          room.viewer.send(JSON.stringify({ type: 'offer', sdp: data.sdp }));
        }
        break;
      }

      case 'answer': {
        const room = getRoomForClient(ws);
        if (!room || ws !== room.viewer || typeof data.sdp !== 'string') return sendError(ws, 'not_allowed');
        if (room.host && room.host.readyState === room.host.OPEN) {
          room.host.send(JSON.stringify({ type: 'answer', sdp: data.sdp }));
        }
        break;
      }

      case 'ice': {
        const room = getRoomForClient(ws);
        if (!room || !data.candidate || typeof data.candidate !== 'object') return sendError(ws, 'not_allowed');
        const other = (ws === room.host) ? room.viewer : room.host;
        if (other && other.readyState === other.OPEN) {
          other.send(JSON.stringify({ type: 'ice', candidate: data.candidate }));
        }
        break;
      }

      case 'end': {
        const room = getRoomForClient(ws);
        if (!room) return sendError(ws, 'not_allowed');
        const other = (ws === room.host) ? room.viewer : room.host;
        if (other && other.readyState === other.OPEN) {
          other.send(JSON.stringify({ type: 'ended' }));
        }
        const code = ws.roomCode;
        if (room.host) { room.host.roomCode = null; room.host.role = null; }
        if (room.viewer) { room.viewer.roomCode = null; room.viewer.role = null; }
        deleteRoom(code);
        break;
      }

      default:
        sendError(ws, 'bad_message');
        break;
    }
  });

  ws.on('close', () => {
    if (!ws.roomCode || !rooms.has(ws.roomCode)) return;
    const room = rooms.get(ws.roomCode);
    if (ws === room.host) {
      if (room.viewer && room.viewer.readyState === room.viewer.OPEN) {
        room.viewer.send(JSON.stringify({ type: 'peer-left' }));
        room.viewer.roomCode = null;
        room.viewer.role = null;
      }
      deleteRoom(ws.roomCode);
    } else if (ws === room.viewer) {
      if (room.host && room.host.readyState === room.host.OPEN) {
        room.host.send(JSON.stringify({ type: 'peer-left' }));
      }
      room.viewer = null;
    }
    ws.roomCode = null;
    ws.role = null;
  });
});

function startServer(p = port) {
  return new Promise((resolve) => {
    server.listen(p, () => {
      console.log(`Server listening on ${p}`);
      resolve(server);
    });
  });
}

if (require.main === module) startServer();

module.exports = { server, wss, rooms, deleteRoom, startServer };
```

---

### `app/lib/services/signaling.dart`
```dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingClient {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  StreamSubscription? _subscription;

  Future<void> connect(String url) async {
    close();
    String normalized = url.trim();
    if (normalized.startsWith('https://')) {
      normalized = 'wss://${normalized.substring(8)}';
    } else if (normalized.startsWith('http://')) {
      normalized = 'ws://${normalized.substring(7)}';
    } else if (!normalized.startsWith('ws://') && !normalized.startsWith('wss://')) {
      normalized = 'wss://$normalized';
    }
    final uri = Uri.parse(normalized);
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;

    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _subscription = channel.stream.listen(
      (data) {
        try {
          if (data is String) {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              _controller?.add(decoded);
            }
          }
        } catch (_) {
          // Ignore malformed payloads
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _controller?.addError(error, stackTrace);
      },
      onDone: () {
        _controller?.close();
      },
    );
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  Stream<Map<String, dynamic>> get messages {
    if (_controller == null) {
      return const Stream.empty();
    }
    return _controller!.stream;
  }

  void close() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _controller?.close();
    _controller = null;
  }
}
```
