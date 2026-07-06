const WebSocket = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;

// Create an HTTP server to handle Render's health checks
const server = http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK');
  } else {
    res.writeHead(404);
    res.end();
  }
});

const wss = new WebSocket.Server({ server });
const peers = new Map();

console.log(`Doro Signaling Server running on port ${PORT}`);

function heartbeat() {
  this.isAlive = true;
}

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.on('pong', heartbeat);

  let registeredId = null;

  ws.on('message', (msg) => {
    try {
      const data = JSON.parse(msg);
      const type = data.type;

      if (type === 'register') {
        registeredId = data.id;
        peers.set(data.id, ws);

        // Confirm registration
        ws.send(JSON.stringify({ type: 'registered', id: registeredId }));

        // notify the new peer of all other peers
        const peerList = Array.from(peers.keys());
        ws.send(JSON.stringify({
          type: 'peer_list',
          peers: peerList,
        }));

        // notify all others about this new peer
        for (const [id, sock] of peers) {
          if (id !== data.id && sock.readyState === WebSocket.OPEN) {
            sock.send(JSON.stringify({
              type: 'peer_list',
              peers: peerList,
            }));
          }
        }

        console.log(`Peer registered: ${data.id} (total: ${peers.size})`);
        return;
      }

      if (type === 'offer' || type === 'answer' || type === 'ice') {
        const targetId = data.to;
        const targetWs = peers.get(targetId);

        if (targetWs && targetWs.readyState === WebSocket.OPEN) {
          targetWs.send(JSON.stringify({
            ...data,
            from: registeredId || data.from,
          }));
        } else {
          ws.send(JSON.stringify({
            type: 'error',
            peerId: targetId,
            message: `Peer ${targetId} not found`,
          }));
        }
        return;
      }

      // broadcast to all other peers for other message types (gossip, etc)
      for (const [id, sock] of peers) {
        if (id !== registeredId && sock.readyState === WebSocket.OPEN) {
          sock.send(JSON.stringify({ ...data, from: registeredId || data.from }));
        }
      }
    } catch (e) {
      console.error('Failed to handle message:', e);
    }
  });

  ws.on('close', () => {
    if (registeredId) {
      if (peers.get(registeredId) === ws) {
        peers.delete(registeredId);
        console.log(`Peer disconnected: ${registeredId} (total: ${peers.size})`);

        const peerList = Array.from(peers.keys());
        for (const [id, sock] of peers) {
          if (sock.readyState === WebSocket.OPEN) {
            sock.send(JSON.stringify({
              type: 'peer_list',
              peers: peerList,
            }));
          }
        }
      }
    }
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
  });
});

// Terminate broken connections every 30s
const interval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) return ws.terminate();
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on('close', () => {
  clearInterval(interval);
});

server.listen(PORT, () => {
  console.log(`Server is listening on port ${PORT}`);
});
