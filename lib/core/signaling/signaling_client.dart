import 'dart:convert';

class SignalingClient {
  Function(Map<String, dynamic>)? onMessage;

  void send(Map<String, dynamic> msg) {
    // placeholder (WebSocket intégré côté backend)
    print("SIGNAL SEND: ${jsonEncode(msg)}");
  }

  void receive(String raw) {
    final msg = jsonDecode(raw);
    onMessage?.call(msg);
  }
}