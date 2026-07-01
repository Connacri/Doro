import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';

class ChatProvider extends ChangeNotifier {
  final P2PNode node;
  final List<Map<String, dynamic>> messages = [];
  StreamSubscription<Map<String, dynamic>>? _sub;
StreamSubscription<void>? _networkSub;          // ← ajouté

  ChatProvider(this.node) {
    _sub = node.messages.listen((msg) {
      if (msg["data"] is Map && msg["data"]["type"] == "chat") {
        messages.add(Map<String, dynamic>.from(msg["data"]));
        notifyListeners();
      }
    });

    _networkSub = node.networkChanges.listen((_) => notifyListeners());  // ← ajouté
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
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
_networkSub?.cancel();
    super.dispose();
  }
}
