const WebSocket = require("ws");

const wss = new WebSocket.Server({ port: 8080 });

const peers = new Map();

wss.on("connection", (ws) => {
  ws.on("message", (msg) => {
    const data = JSON.parse(msg);

    if (data.type === "register") {
      peers.set(data.id, ws);
    }

    if (data.to && peers.has(data.to)) {
      peers.get(data.to).send(JSON.stringify(data));
    }
  });
});