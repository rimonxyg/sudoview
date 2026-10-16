const http = require('http');
const { WebSocketServer } = require('ws');

const port = process.env.PORT || 8082;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('TeachView Signaling Server\n');
});

const wss = new WebSocketServer({ server });

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

module.exports = { server, wss, startServer };

