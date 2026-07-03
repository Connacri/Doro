import 'dart:convert';
import 'peer_connection.dart';
import 'peer_model.dart';

class WebRTCNetworkEngine {
  final Map<String, PeerConnection> _connections = {};
  final Map<String, Peer> peers = {};
  final Map<String, dynamic> _pendingOffers = {};

  Function(String from, String msg)? onMessage;
  void Function(String peerId)? onPeerConnected;
  void Function(String peerId)? onPeerDisconnected;
  void Function(String peerId, Map<String, dynamic> candidate)? onIceCandidate;
  void Function(String peerId)? onChannelOpen;

  void registerPeer(Peer peer) {
    final isNew = !peers.containsKey(peer.id);
    peers[peer.id] = peer;
    if (isNew) onPeerConnected?.call(peer.id);
  }

  Future<void> connectPeer(Peer peer) async {
    registerPeer(peer);
    await createOffer(peer.id);
  }

  Future<Map<String, dynamic>?> createOffer(String peerId) async {
    final conn = PeerConnection();
    await conn.init();

    conn.onMessage = (msg) {
      onMessage?.call(peerId, msg);
    };
    conn.onDisconnect(() => removePeer(peerId));
    conn.onIceCandidate((candidate) => onIceCandidate?.call(peerId, candidate));
    conn.onChannelOpen(() => onChannelOpen?.call(peerId));

    await conn.createChannel();
    final offer = await conn.createOffer();
    _connections[peerId] = conn;
    _pendingOffers[peerId] = conn;
    return offer;
  }

  Future<void> handleAnswer(String peerId, dynamic sdp) async {
    final conn = _connections[peerId];
    if (conn == null) return;
    await conn.setRemoteDescription(sdp);
  }

  Future<Map<String, dynamic>?> acceptConnection(String peerId, dynamic sdp) async {
    final conn = PeerConnection();
    await conn.init();

    conn.onMessage = (msg) {
      onMessage?.call(peerId, msg);
    };
    conn.onDisconnect(() => removePeer(peerId));
    conn.onIceCandidate((candidate) => onIceCandidate?.call(peerId, candidate));
    conn.onChannelOpen(() => onChannelOpen?.call(peerId));

    await conn.setRemoteDescription(sdp);
    final answer = await conn.createAnswer();
    _connections[peerId] = conn;
    registerPeer(Peer(id: peerId, address: "", lastSeen: DateTime.now()));
    return answer;
  }

  Future<void> handleIce(String peerId, dynamic candidate) async {
    final conn = _connections[peerId];
    if (conn == null) return;
    await conn.addIceCandidate(candidate);
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
    final existed = peers.remove(peerId) != null;
    if (existed) onPeerDisconnected?.call(peerId);
  }

  Future<void> dispose() async {
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    peers.clear();
  }
}