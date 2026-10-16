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
      if (room.host && room.host.readyState === room.host.OPEN) {
        room.host.close();
      }
      if (room.viewer && room.viewer.readyState === room.viewer.OPEN) {
        room.viewer.close();
      }
      deleteRoom(code);
    }
  }
}

let cleanupInterval = setInterval(() => sweepRooms(), CLEANUP_INTERVAL_MS);
if (cleanupInterval && cleanupInterval.unref) {
  cleanupInterval.unref();
}

function stopCleanup() {
  if (cleanupInterval) {
    clearInterval(cleanupInterval);
    cleanupInterval = null;
  }
  for (const [code] of rooms.entries()) {
    deleteRoom(code);
  }
}

function sendError(ws, message) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify({ type: 'error', message }));
  }
}

function getRoomForClient(ws) {
  if (!ws.roomCode || !rooms.has(ws.roomCode)) {
    return null;
  }
  const room = rooms.get(ws.roomCode);
  if (room.host !== ws && room.viewer !== ws) {
    return null;
  }
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
        if (!room || ws !== room.host) {
          return sendError(ws, 'not_allowed');
        }
        if (!room.viewer) {
          return sendError(ws, 'not_allowed');
        }
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
        if (!room || ws !== room.host) {
          return sendError(ws, 'not_allowed');
        }
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
        if (!room || ws !== room.host) {
          return sendError(ws, 'not_allowed');
        }
        if (typeof data.sdp !== 'string') {
          return sendError(ws, 'bad_message');
        }
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
        if (!room || ws !== room.viewer) {
          return sendError(ws, 'not_allowed');
        }
        if (typeof data.sdp !== 'string') {
          return sendError(ws, 'bad_message');
        }
        if (room.host && room.host.readyState === room.host.OPEN) {
          room.host.send(JSON.stringify({ type: 'answer', sdp: data.sdp }));
        }
        break;
      }

      case 'ice': {
        const room = getRoomForClient(ws);
        if (!room) {
          return sendError(ws, 'not_allowed');
        }
        if (!data.candidate || typeof data.candidate !== 'object') {
          return sendError(ws, 'bad_message');
        }
        const other = (ws === room.host) ? room.viewer : room.host;
        if (other && other.readyState === other.OPEN) {
          other.send(JSON.stringify({ type: 'ice', candidate: data.candidate }));
        }
        break;
      }

      case 'end': {
        const room = getRoomForClient(ws);
        if (!room) {
          return sendError(ws, 'not_allowed');
        }
        const other = (ws === room.host) ? room.viewer : room.host;
        if (other && other.readyState === other.OPEN) {
          other.send(JSON.stringify({ type: 'ended' }));
        }
        const code = ws.roomCode;
        if (room.host) {
          room.host.roomCode = null;
          room.host.role = null;
        }
        if (room.viewer) {
          room.viewer.roomCode = null;
          room.viewer.role = null;
        }
        deleteRoom(code);
        break;
      }

      default:
        sendError(ws, 'bad_message');
        break;
    }
  });

  ws.on('close', () => {
    if (!ws.roomCode || !rooms.has(ws.roomCode)) {
      return;
    }
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

if (require.main === module) {
  startServer();
}

module.exports = {
  server,
  wss,
  rooms,
  deleteRoom,
  startServer,
  sweepRooms,
  stopCleanup,
  cleanupInterval,
  ROOM_TIMEOUT_MS
};
