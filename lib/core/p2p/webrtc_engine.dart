import 'dart:async';
import 'dart:convert';
import '../utils/logger.dart';
import 'peer_connection.dart';
import 'peer_model.dart';

class WebRTCNetworkEngine {
  final String nodeId;
  final Map<String, PeerConnection> _connections = {};
  final Map<String, Peer> peers = {};

  // Buffer for ICE candidates that arrive before the connection is established
  final Map<String, List<Map<String, dynamic>>> _iceBuffer = {};

  final _messageController = StreamController<({String from, dynamic data})>.broadcast();
  Stream<({String from, dynamic data})> get messages => _messageController.stream;

  void Function(String peerId)? onPeerConnected;
  void Function(String peerId)? onPeerDisconnected;
  void Function(String peerId, Map<String, dynamic> candidate)? onIceCandidate;
  void Function(String peerId)? onChannelOpen;

  WebRTCNetworkEngine(this.nodeId);

  void registerPeer(Peer peer) {
    final isNew = !peers.containsKey(peer.id);
    peers[peer.id] = peer;
    if (isNew) onPeerConnected?.call(peer.id);
  }

  void _registerOnceChannelOpen(String peerId) {
    registerPeer(Peer(id: peerId, address: "", lastSeen: DateTime.now()));
  }

  Future<Map<String, dynamic>?> createOffer(String peerId) async {
    if (_connections.containsKey(peerId)) return null;

    Logger.info("WebRTC: Creating offer for $peerId");
    final conn = PeerConnection();
    _connections[peerId] = conn; // Register early to handle incoming ICE

    Logger.info("WebRTC: Calling conn.init() for $peerId");
    await conn.init();
    Logger.info("WebRTC: conn.init() finished for $peerId");

    conn.onMessage = (msg) {
      try {
        final data = jsonDecode(msg);
        _messageController.add((from: peerId, data: data));
      } catch (e) {
        Logger.warn("Failed to decode message from $peerId: $e");
      }
    };
    conn.onDisconnect(() => removePeer(peerId));
    conn.onIceCandidate((candidate) => onIceCandidate?.call(peerId, candidate));
    conn.onChannelOpen(() {
      _registerOnceChannelOpen(peerId);
      onChannelOpen?.call(peerId);
    });

    Logger.info("WebRTC: Calling conn.createChannel() for $peerId");
    await conn.createChannel();
    Logger.info("WebRTC: conn.createChannel() finished for $peerId");

    Logger.info("WebRTC: Calling conn.createOffer() for $peerId");
    final offer = await conn.createOffer();
    Logger.info("WebRTC: conn.createOffer() finished for $peerId");

    // Flush buffered ICE candidates
    _flushIceBuffer(peerId);

    return offer;
  }

  Future<void> handleAnswer(String peerId, dynamic sdp) async {
    final conn = _connections[peerId];
    if (conn == null) {
      Logger.warn("WebRTC: Received answer from unknown peer $peerId");
      return;
    }
    await conn.setRemoteDescription(sdp);
    _flushIceBuffer(peerId);
  }

  Future<Map<String, dynamic>?> acceptConnection(String peerId, dynamic sdp) async {
    if (_connections.containsKey(peerId)) {
       // If negotiation is already in progress, don't overwrite
       if (_connections[peerId]!.isOpen) return null;
    }

    Logger.info("WebRTC: Accepting connection from $peerId");
    final conn = PeerConnection();
    _connections[peerId] = conn; // Register early

    await conn.init();

    conn.onMessage = (msg) {
      try {
        final data = jsonDecode(msg);
        _messageController.add((from: peerId, data: data));
      } catch (e) {
        Logger.warn("Failed to decode message from $peerId: $e");
      }
    };
    conn.onDisconnect(() => removePeer(peerId));
    conn.onIceCandidate((candidate) => onIceCandidate?.call(peerId, candidate));
    conn.onChannelOpen(() {
      _registerOnceChannelOpen(peerId);
      onChannelOpen?.call(peerId);
    });

    await conn.setRemoteDescription(sdp);
    final answer = await conn.createAnswer();

    // Flush buffered ICE candidates
    _flushIceBuffer(peerId);

    return answer;
  }

  Future<void> handleIce(String peerId, dynamic candidate) async {
    final conn = _connections[peerId];
    if (conn == null) {
      // Buffer ICE candidate if connection not yet created
      Logger.info("WebRTC: Buffering ICE candidate for $peerId");
      _iceBuffer.putIfAbsent(peerId, () => []).add(Map<String, dynamic>.from(candidate));
      return;
    }

    try {
       await conn.addIceCandidate(candidate);
    } catch (e) {
       Logger.warn("WebRTC: Failed to add ICE candidate for $peerId: $e");
       // Buffer it anyway if it failed (maybe too early)
       _iceBuffer.putIfAbsent(peerId, () => []).add(Map<String, dynamic>.from(candidate));
    }
  }

  void _flushIceBuffer(String peerId) {
    final buffered = _iceBuffer.remove(peerId);
    if (buffered != null && buffered.isNotEmpty) {
      Logger.info("WebRTC: Flushing ${buffered.length} buffered ICE candidates for $peerId");
      final conn = _connections[peerId];
      if (conn != null) {
        for (final cand in buffered) {
          conn.addIceCandidate(cand).catchError((e) {
             Logger.warn("WebRTC: Error flushing ICE candidate: $e");
          });
        }
      }
    }
  }

  bool sendToPeer(String peerId, Map<String, dynamic> data) {
    final conn = _connections[peerId];
    if (conn == null) return false;
    return conn.send(jsonEncode(data));
  }

  bool isConnectedTo(String peerId) => _connections.containsKey(peerId);

  bool isPeerChannelOpen(String peerId) => _connections[peerId]?.isOpen ?? false;

  void broadcast(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    for (final conn in _connections.values) {
      conn.send(encoded);
    }
  }

  void removePeer(String peerId) {
    Logger.info("WebRTC: Removing peer $peerId");
    _connections[peerId]?.close();
    _connections.remove(peerId);
    _iceBuffer.remove(peerId);
    final existed = peers.remove(peerId) != null;
    if (existed) onPeerDisconnected?.call(peerId);
  }

  Future<void> dispose() async {
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    _iceBuffer.clear();
    peers.clear();
    await _messageController.close();
  }
}
