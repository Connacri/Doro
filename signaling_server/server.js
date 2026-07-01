const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocket.Server({ port: PORT });
const peers = new Map();

console.log(`Volte Signaling Server running on port ${PORT}`);

wss.on('connection', (ws) => {
  let registeredId = null;

  ws.on('message', (msg) => {
    try {
      const data = JSON.parse(msg);
      const type = data.type;

      if (type === 'register') {
        registeredId = data.id;
        peers.set(data.id, ws);

        // notify the new peer of all other peers
        const peerList = Array.from(peers.keys());
        ws.send(JSON.stringify({
          type: 'peer_list',
          peers: peerList,
        }));

        // notify all others about this new peer
        for (const [id, sock] of peers) {
          if (id !== data.id) {
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
            from: registeredId,
          }));
        } else {
          ws.send(JSON.stringify({
            type: 'error',
            message: `Peer ${targetId} not found`,
          }));
        }
        return;
      }

      // broadcast to all other peers
      for (const [id, sock] of peers) {
        if (id !== registeredId && sock.readyState === WebSocket.OPEN) {
          sock.send(JSON.stringify({ ...data, from: registeredId }));
        }
      }
    } catch (e) {
      console.error('Failed to handle message:', e);
    }
  });

  ws.on('close', () => {
    if (registeredId) {
      peers.delete(registeredId);
      console.log(`Peer disconnected: ${registeredId} (total: ${peers.size})`);

      // notify remaining peers
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
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message);
  });
});
