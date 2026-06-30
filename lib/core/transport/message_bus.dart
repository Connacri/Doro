import 'dart:convert';

class MessageBus {
  final Map<String, Function(Map<String, dynamic>)> _routes = {};

  void on(String type, Function(Map<String, dynamic>) handler) {
    _routes[type] = handler;
  }

  void emit(String raw) {
    final msg = jsonDecode(raw);
    final type = msg["type"];

    if (_routes.containsKey(type)) {
      _routes[type]!(msg);
    }
  }

  String encode(Map<String, dynamic> msg) {
    return jsonEncode(msg);
  }
}