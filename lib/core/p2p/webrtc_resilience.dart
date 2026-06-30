import 'dart:async';
import 'peer_connection.dart';

class WebRTCResilience {
  final Map<String, PeerConnection> _connections = {};
  final Map<String, int> _retryCount = {};

  void register(String peerId, PeerConnection conn) {
    _connections[peerId] = conn;
    _retryCount[peerId] = 0;
  }

  void markFailure(String peerId) {
    _retryCount[peerId] = (_retryCount[peerId] ?? 0) + 1;

    if (_retryCount[peerId]! > 3) {
      _connections[peerId]?.close();
      _connections.remove(peerId);
    }
  }

  Future<void> reconnect(String peerId, Future<PeerConnection> Function() factory) async {
    if ((_retryCount[peerId] ?? 0) > 3) return;

    final conn = await factory();
    _connections[peerId] = conn;
  }
}