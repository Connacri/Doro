import 'dart:convert';
import 'peer_connection.dart';
import 'peer_model.dart';

class WebRTCNetworkEngine {
  final Map<String, PeerConnection> _connections = {};
  final Map<String, Peer> peers = {};

  Function(String from, String msg)? onMessage;

  Future<void> connectPeer(Peer peer) async {
    final conn = PeerConnection();
    await conn.init();

    conn.onMessage = (msg) {
      onMessage?.call(peer.id, msg);
    };

    await conn.createChannel();

    _connections[peer.id] = conn;
    peers[peer.id] = peer;
  }

  void sendToPeer(String peerId, Map<String, dynamic> data) {
    final conn = _connections[peerId];
    if (conn == null) return;

    conn.send(jsonEncode(data));
  }

  void broadcast(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);

    for (final conn in _connections.values) {
      conn.send(encoded);
    }
  }

  void removePeer(String peerId) {
    _connections[peerId]?.close();
    _connections.remove(peerId);
    peers.remove(peerId);
  }
}