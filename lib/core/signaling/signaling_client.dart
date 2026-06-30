import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingClient {
  final WebSocketChannel _channel;

  Function(Map<String, dynamic>)? onMessage;

  SignalingClient(String url)
      : _channel = WebSocketChannel.connect(Uri.parse(url)) {
    _channel.stream.listen((event) {
      onMessage?.call(jsonDecode(event));
    });
  }

  void send(Map<String, dynamic> msg) {
    _channel.sink.add(jsonEncode(msg));
  }

  void close() {
    _channel.sink.close();
  }
}