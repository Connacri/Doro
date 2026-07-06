import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../utils/logger.dart';

class SignalingClient {
  final List<String> urls;
  int _urlIndex = 0;
  String get url => urls[_urlIndex];

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isClosed = false;
  bool _wasConnected = false;

  Timer? _reconnectTimer;

  Function(Map<String, dynamic>)? onMessage;
  Function()? onConnect;
  Function()? onDisconnect;

  SignalingClient(this.urls) : assert(urls.isNotEmpty, "SignalingClient nécessite au moins une URL") {
    _connect();
  }

  void _connect() {
    if (_isClosed) return;

    Logger.info("Connecting to signaling server ($_urlIndex/${urls.length - 1}): $url");
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.ready.then((_) {
        if (_isClosed) return;
        _wasConnected = true;
        Logger.info("Signaling WebSocket handshake established");
        onConnect?.call();
      }).catchError((e) {
        Logger.error("Signaling WebSocket handshake failed: $e");
        _reconnect();
      });

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

    if (_wasConnected) {
      _wasConnected = false;
      onDisconnect?.call();
    }

    _subscription?.cancel();
    _channel?.sink.close();

    _urlIndex = (_urlIndex + 1) % urls.length;

    Logger.info("Reconnecting to signaling server ($url) in 5 seconds...");
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }

  void retryNow() {
    if (_isClosed) return;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _connect();
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
    if (_wasConnected) {
      _wasConnected = false;
      onDisconnect?.call();
    }
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
