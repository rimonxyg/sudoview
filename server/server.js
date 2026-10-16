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
          createdAt: Date.now()
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

      default:
        sendError(ws, 'bad_message');
        break;
    }
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
