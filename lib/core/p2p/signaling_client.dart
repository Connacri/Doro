import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/logger.dart';

class SignalingClient {
  final String url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isClosed = false;

  Function(Map<String, dynamic>)? onMessage;
  Function()? onConnect;

  SignalingClient(this.url) {
    _connect();
  }

  void _connect() {
    if (_isClosed) return;

    Logger.info("Connecting to signaling server: $url");
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      // In web_socket_channel, we don't have a direct "onOpen".
      // It's usually considered connected when we start listening or sending.
      // We'll trigger onConnect immediately after connect call for simplicity,
      // or we could wait for the first message if the server sends one.
      // But re-registering is usually safe to do immediately.
      onConnect?.call();

      _subscription = _channel!.stream.listen(
        (event) {
          try {
            final data = jsonDecode(event);
            onMessage?.call(data);
          } catch (e) {
            Logger.error("Failed to decode signaling message: $e");
          }
        },
        onError: (error) {
          Logger.error("Signaling WebSocket error: $error");
          _reconnect();
        },
        onDone: () {
          Logger.info("Signaling WebSocket connection closed");
          _reconnect();
        },
      );
    } catch (e) {
      Logger.error("Failed to connect to signaling server: $e");
      _reconnect();
    }
  }

  void _reconnect() {
    if (_isClosed) return;

    _subscription?.cancel();
    _channel?.sink.close();

    Logger.info("Reconnecting to signaling server in 5 seconds...");
    Timer(const Duration(seconds: 5), _connect);
  }

  void send(Map<String, dynamic> msg) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(msg));
      } catch (e) {
        Logger.error("Failed to send signaling message: $e");
      }
    } else {
      Logger.error("Cannot send message: SignalingClient not connected");
    }
  }

  void close() {
    _isClosed = true;
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
