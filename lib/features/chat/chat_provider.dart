import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';

class ChatProvider extends ChangeNotifier {
  final P2PNode node;

  final List<Map<String, dynamic>> messages = [];

  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _networkSub;

  ChatProvider(this.node) {
    _sub = node.messages.listen((msg) {
      final data = msg["data"];

      if (data is Map && data["type"] == "chat") {
        messages.add(Map<String, dynamic>.from(data));

        if (hasListeners) {
          notifyListeners();
        }
      }
    });

    _networkSub = node.networkChanges.listen((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  List<String> get onlinePeers =>
      node.p2p.peers.keys.where((id) => id != node.nodeId).toList();

  String get myId => node.nodeId;

  void send(String text) {
    if (text.trim().isEmpty) return;

    node.sendChat(text);

    messages.add({
      "from": node.nodeId,
      "text": text,
      "time": DateTime.now().toIso8601String(),
    });

    if (hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}