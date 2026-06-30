import 'package:flutter/material.dart';

class ChatProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> messages = [];

  void send(String from, String text) {
    messages.add({
      "from": from,
      "text": text,
      "time": DateTime.now().toIso8601String()
    });

    notifyListeners();
  }
}