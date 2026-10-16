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

        rooms.set(code, {
          host: ws,
          viewer: null,
          createdAt: Date.now(),
          sessionStarted: false
        });

        ws.roomCode = code;
        ws.role = 'host';

        ws.send(JSON.stringify({ type: 'created', code }));
        break;
      }

      case 'join': {
        const { code } = data;
        if (!code || typeof code !== 'string' || !rooms.has(code)) {
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
        rooms.delete(code);
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
      rooms.delete(ws.roomCode);
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

module.exports = { server, wss, rooms, startServer };
