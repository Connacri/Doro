import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'peer_connection.dart';
import 'signaling_client.dart';

class WebRTCNetworkEngine {
  final SignalingClient signaling;
  final String myId;
  final Map<String, PeerConnection> _connections = {};

  Function(String from, String msg)? onMessage;

  WebRTCNetworkEngine({required this.signaling, required this.myId}) {
    signaling.onMessage = _handleSignalingMessage;
  }

  void _handleSignalingMessage(Map<String, dynamic> data) async {
    final from = data["from_node"];
    if (from == null) return;

    if (data["type"] == "offer") {
      final pc = await _getOrCreateConnection(from);
      final offer = RTCSessionDescription(data["sdp"], data["type"]);
      final answer = await pc.createAnswer(offer);
      
      signaling.sendSignal(from, {
        "type": "answer",
        "sdp": answer.sdp,
        "from_node": myId,
      });
    } else if (data["type"] == "answer") {
      final pc = _connections[from];
      if (pc != null) {
        final answer = RTCSessionDescription(data["sdp"], data["type"]);
        await pc.setRemoteDescription(answer);
      }
    } else if (data["type"] == "candidate") {
      final pc = _connections[from];
      if (pc != null) {
        final candidate = RTCIceCandidate(
          data["candidate"],
          data["sdpMid"],
          data["sdpMLineIndex"],
        );
        await pc.addCandidate(candidate);
      }
    }
  }

  Future<PeerConnection> _getOrCreateConnection(String peerId) async {
    if (_connections.containsKey(peerId)) return _connections[peerId]!;

    final pc = PeerConnection();
    await pc.init();
    
    pc.onMessage = (msg) => onMessage?.call(peerId, msg);
    
    pc.onIceCandidate = (candidate) {
      signaling.sendSignal(peerId, {
        "type": "candidate",
        "candidate": candidate.candidate,
        "sdpMid": candidate.sdpMid,
        "sdpMLineIndex": candidate.sdpMLineIndex,
        "from_node": myId,
      });
    };

    _connections[peerId] = pc;
    return pc;
  }

  Future<void> connectToPeer(String peerId) async {
    final pc = await _getOrCreateConnection(peerId);
    final offer = await pc.createOffer();
    
    signaling.sendSignal(peerId, {
      "type": "offer",
      "sdp": offer.sdp,
      "from_node": myId,
    });
  }

  void broadcast(String message) {
    for (final conn in _connections.values) {
      conn.send(message);
    }
  }

  void sendTo(String peerId, String message) {
    _connections[peerId]?.send(message);
  }
}
