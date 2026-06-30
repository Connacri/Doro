import 'package:flutter_webrtc/flutter_webrtc.dart';

class PeerConnection {
  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;

  Function(String msg)? onMessage;

  Future<void> init() async {
    final config = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"}
      ]
    };

    _pc = await createPeerConnection(config);

    _pc!.onDataChannel = (channel) {
      _channel = channel;

      _channel!.onMessage = (msg) {
        onMessage?.call(msg.text);
      };
    };
  }

  Future<RTCDataChannel> createChannel() async {
    final channel = await _pc!.createDataChannel(
      "p2p",
      RTCDataChannelInit()..ordered = true,
    );

    _channel = channel;

    _channel!.onMessage = (msg) {
      onMessage?.call(msg.text);
    };

    return channel;
  }

  void send(String message) {
    _channel?.send(RTCDataChannelMessage(message));
  }

  Future<void> close() async {
    await _channel?.close();
    await _pc?.close();
  }
}