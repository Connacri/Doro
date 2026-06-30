import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingClient {
  final WebSocketChannel channel;

  Function(Map<String, dynamic> msg)? onMessage;

  SignalingClient(String url)
      : channel = WebSocketChannel.connect(Uri.parse(url)) {
    channel.stream.listen((event) {
      final data = jsonDecode(event);
      onMessage?.call(data);
    });
  }

  void register(String nodeId) {
    channel.sink.add(jsonEncode({
      "type": "register",
      "id": nodeId,
    }));
  }

  void sendSignal(String to, Map<String, dynamic> data) {
    channel.sink.add(jsonEncode({
      "to": to,
      ...data,
    }));
  }

  void dispose() {
    channel.sink.close();
  }
}