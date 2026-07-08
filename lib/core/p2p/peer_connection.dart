import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../utils/logger.dart';

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
    Logger.info("PeerConnection: Wiring data channel");
    _channel = channel;
    _channel!.onMessage = (msg) {
      Logger.info("PeerConnection: Received data channel message");
      onMessage?.call(msg.text);
    };
    _channel!.onDataChannelState = (state) {
      Logger.info("PeerConnection: Data channel state changed to $state");
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _isOpen = true;
        _onChannelOpen?.call();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _isOpen = false;
      }
    };
  }

  Future<void> init() async {
    Logger.info("PeerConnection: Initializing RTCPeerConnection...");
    
    // Grouping STUN and TURN configuration. 
    // Omitting '?transport=tcp' to avoid native parsing crashes on Windows desktop.
    final config = {
      "sdpSemantics": "unified-plan",
      "iceServers": [
        {"urls": ["stun:stun.l.google.com:19302"]},
        {"urls": ["stun:stun1.l.google.com:19302"]},
        {"urls": ["stun:stun2.l.google.com:19302"]},
        {"urls": ["stun:stun3.l.google.com:19302"]},
        {"urls": ["stun:stun4.l.google.com:19302"]},
        {
          "urls": [
            "turn:openrelay.metered.ca:80",
            "turn:openrelay.metered.ca:443"
          ],
          "username": "openrelayproject",
          "credential": "openrelayproject",
        }
      ]
    };

    try {
      Logger.info("PeerConnection: Calling createPeerConnection(config)...");
      _pc = await createPeerConnection(config);
      Logger.info("PeerConnection: createPeerConnection completed successfully.");

      _pc!.onDataChannel = (channel) {
        Logger.info("PeerConnection: onDataChannel event fired");
        _wireChannel(channel);
      };

      _pc!.onIceCandidate = (candidate) {
        Logger.info("PeerConnection: onIceCandidate event fired");
        if (_onIceCandidate != null) {
          _onIceCandidate!(candidate.toMap());
        }
      };

      _pc!.onIceConnectionState = (state) {
        Logger.info("PeerConnection: onIceConnectionState changed to $state");
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
            state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          _onDisconnect?.call();
        }
      };
    } catch (e, stack) {
      Logger.error("PeerConnection: Exception in init(): $e\n$stack");
      rethrow;
    }
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
    Logger.info("PeerConnection: Creating offer...");
    try {
      final offer = await _pc!.createOffer();
      Logger.info("PeerConnection: Offer created. Setting local description...");
      await _pc!.setLocalDescription(offer);
      Logger.info("PeerConnection: Local description set successfully.");
      return offer.toMap();
    } catch (e, stack) {
      Logger.error("PeerConnection: Exception in createOffer(): $e\n$stack");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createAnswer() async {
    Logger.info("PeerConnection: Creating answer...");
    try {
      final answer = await _pc!.createAnswer();
      Logger.info("PeerConnection: Answer created. Setting local description...");
      await _pc!.setLocalDescription(answer);
      Logger.info("PeerConnection: Local description set successfully.");
      return answer.toMap();
    } catch (e, stack) {
      Logger.error("PeerConnection: Exception in createAnswer(): $e\n$stack");
      rethrow;
    }
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    Logger.info("PeerConnection: Setting remote description...");
    try {
      final desc = RTCSessionDescription(sdp["sdp"], sdp["type"]);
      await _pc!.setRemoteDescription(desc);
      Logger.info("PeerConnection: Remote description set successfully.");
    } catch (e, stack) {
      Logger.error("PeerConnection: Exception in setRemoteDescription(): $e\n$stack");
      rethrow;
    }
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidate) async {
    if (_pc == null) {
      Logger.info("PeerConnection: Cannot add ICE candidate yet, _pc is null (will be buffered)");
      throw StateError("RTCPeerConnection is not initialized");
    }
    Logger.info("PeerConnection: Adding ICE candidate...");
    try {
      final cand = RTCIceCandidate(
        candidate["candidate"],
        candidate["sdpMid"],
        candidate["sdpMLineIndex"],
      );
      await _pc!.addCandidate(cand);
      Logger.info("PeerConnection: ICE candidate added successfully.");
    } catch (e, stack) {
      Logger.error("PeerConnection: Exception in addIceCandidate(): $e\n$stack");
      rethrow;
    }
  }

  Future<RTCDataChannel> createChannel() async {
    Logger.info("PeerConnection: Creating data channel 'p2p'...");
    try {
      final channel = await _pc!.createDataChannel(
        "p2p",
        RTCDataChannelInit()..ordered = true,
      );
      Logger.info("PeerConnection: Data channel created successfully.");
      _wireChannel(channel);
      return channel;
    } catch (e, stack) {
      Logger.error("PeerConnection: Exception in createChannel(): $e\n$stack");
      rethrow;
    }
  }

  bool send(String message) {
    if (!_isOpen) {
      Logger.warn("PeerConnection: Cannot send message, data channel is not open");
      return false;
    }
    try {
      _channel?.send(RTCDataChannelMessage(message));
      return true;
    } catch (e) {
      Logger.error("PeerConnection: Exception in send(): $e");
      return false;
    }
  }

  Future<void> close() async {
    Logger.info("PeerConnection: Closing connection...");
    try {
      await _channel?.close();
      await _pc?.close();
      Logger.info("PeerConnection: Connection closed successfully.");
    } catch (e) {
      Logger.error("PeerConnection: Exception in close(): $e");
    }
  }
}
