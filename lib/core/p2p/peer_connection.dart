import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class PeerConnection {
  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;

  Function(String msg)? onMessage;
  Function(RTCIceCandidate candidate)? onIceCandidate;
  Function(RTCSessionDescription sdp)? onDescription;
  Function(RTCDataChannelState state)? onChannelStateChange;

  final Map<String, dynamic> _config = {
    "iceServers": [
      {"urls": "stun:stun.l.google.com:19302"},
      {"urls": "stun:stun1.l.google.com:19302"},
    ]
  };

  Future<void> init() async {
    _pc = await createPeerConnection(_config);

    _pc!.onIceCandidate = (candidate) {
      onIceCandidate?.call(candidate);
    };

    _pc!.onDataChannel = (channel) {
      _setupDataChannel(channel);
    };

    _pc!.onConnectionState = (state) {
      print("Connection state changed: $state");
    };
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _channel = channel;
    _channel!.onMessage = (msg) {
      onMessage?.call(msg.text);
    };
    _channel!.onDataChannelState = (state) {
      onChannelStateChange?.call(state);
    };
  }

  Future<RTCSessionDescription> createOffer() async {
    final channel = await _pc!.createDataChannel(
      "p2p_data",
      RTCDataChannelInit()..ordered = true,
    );
    _setupDataChannel(channel);

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer(RTCSessionDescription offer) async {
    await _pc!.setRemoteDescription(offer);
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription desc) async {
    await _pc!.setRemoteDescription(desc);
  }

  Future<void> addCandidate(RTCIceCandidate candidate) async {
    await _pc!.addCandidate(candidate);
  }

  void send(String message) {
    if (_channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _channel?.send(RTCDataChannelMessage(message));
    } else {
      print("Data channel not open. State: ${_channel?.state}");
    }
  }

  Future<void> close() async {
    await _channel?.close();
    await _pc?.close();
  }
}
