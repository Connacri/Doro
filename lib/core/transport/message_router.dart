import 'dart:convert';

class MessageRouter {
  Function(Map<String, dynamic> msg)? onTx;
  Function(Map<String, dynamic> msg)? onChat;

  void route(String raw, String from) {
    final data = Map<String, dynamic>.from(
      jsonDecode(raw),
    );

    switch (data["type"]) {
      case "tx":
        onTx?.call(data);
        break;

      case "chat":
        onChat?.call(data);
        break;
    }
  }
}