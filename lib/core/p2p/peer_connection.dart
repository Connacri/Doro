import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class PeerConnection {
  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  bool _isOpen = false;

  Function(String msg)? onMessage;
  void Function()? _onChannelOpen;

  bool get isOpen => _isOpen;

  void onChannelOpen(void Function() cb) {
    _onChannelOpen = cb;
  }

  void _wireChannel(RTCDataChannel channel) {
    _channel = channel;
    _channel!.onMessage = (msg) {
      onMessage?.call(msg.text);
    };
    _channel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _isOpen = true;
        _onChannelOpen?.call();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _isOpen = false;
      }
    };
  }

  Future<void> init() async {
    final config = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"},
        {"urls": "stun:stun1.l.google.com:19302"},
      ]
    };

    _pc = await createPeerConnection(config);

    _pc!.onDataChannel = (channel) {
      _wireChannel(channel);
    };

    _pc!.onIceCandidate = (candidate) {
      if (_onIceCandidate != null) {
        _onIceCandidate!(candidate.toMap());
      }
    };

    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _onDisconnect?.call();
      }
    };
  }

  void Function(Map<String, dynamic>)? _onIceCandidate;
  void onIceCandidate(void Function(Map<String, dynamic>) cb) {
    _onIceCandidate = cb;
  }

  void Function()? _onDisconnect;
  void onDisconnect(void Function() cb) {
    _onDisconnect = cb;
  }

  Future<Map<String, dynamic>> createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    return offer.toMap();
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    return answer.toMap();
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    final desc = RTCSessionDescription(sdp["sdp"], sdp["type"]);
    await _pc!.setRemoteDescription(desc);
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    final cand = RTCIceCandidate(
      candidate["candidate"],
      candidate["sdpMid"],
      candidate["sdpMLineIndex"],
    );
    await _pc!.addCandidate(cand);
  }

  Future<RTCDataChannel> createChannel() async {
    final channel = await _pc!.createDataChannel(
      "p2p",
      RTCDataChannelInit()..ordered = true,
    );

    _wireChannel(channel);

    return channel;
  }

  /// Retourne `true` si le message a effectivement été transmis au canal
  /// WebRTC, `false` s'il a été silencieusement abandonné (canal pas
  /// encore ouvert, ex: négociation ICE en cours ou pair déconnecté).
  /// L'appelant DOIT vérifier cette valeur : un `false` signifie que le
  /// message n'a jamais quitté l'appareil et doit être mis en file
  /// d'attente pour un renvoi ultérieur (voir MessengerKernel.outbox).
  bool send(String message) {
    if (!_isOpen) return false;
    _channel?.send(RTCDataChannelMessage(message));
    return true;
  }

  Future<void> close() async {
    await _channel?.close();
    await _pc?.close();
  }
}
