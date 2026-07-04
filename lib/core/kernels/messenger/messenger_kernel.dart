// lib/core/kernels/messenger/messenger_kernel.dart
import 'dart:async';
import '../../p2p/webrtc_engine.dart';
import '../../storage/objectbox/store.dart';
import '../../storage/entities/chat_message_entity.dart';
import '../../../objectbox.g.dart';

class MessengerKernel {
  final String nodeId;
  final WebRTCNetworkEngine p2p;
  final ObjectBoxStore db;
  late final Box<ChatMessageEntity> _msgBox;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final Set<String> _seenChatMessages = {};

  MessengerKernel({required this.nodeId, required this.p2p, required this.db}) {
    _msgBox = db.getBox<ChatMessageEntity>();
    p2p.messages.listen((msg) {
      final data = msg.data;
      final from = msg.from;
      if (data is Map<String, dynamic> && data["type"] == "chat") {
        _handleIncomingChat(from, data);
      }
    });
  }

  void _handleIncomingChat(String from, Map<String, dynamic> data) {
    final fromId = data["from"] as String?;
    final toId = data["to"] as String?;
    final text = data["text"] as String?;
    final time = data["time"] as String?;
    if (fromId == null || text == null || time == null) return;
    if (fromId == nodeId) return;
    // Message privé : accepté seulement s'il nous est destiné.
    // Contrairement à l'ancien chat global, AUCUN re-broadcast.
    if (toId != null && toId != nodeId) return;

    final msgKey = "$fromId:$time:${text.hashCode}";
    if (_seenChatMessages.contains(msgKey)) return;
    _seenChatMessages.add(msgKey);

    _msgBox.put(ChatMessageEntity(fromId: fromId, text: text, timestamp: time, peerKey: fromId));
    _messageController.add({"from": from, "data": data});
  }

  void sendPrivateChat(String toPeerId, String text) {
    final time = DateTime.now().toIso8601String();
    final data = {"type": "chat", "from": nodeId, "to": toPeerId, "text": text, "time": time};

    _seenChatMessages.add("$nodeId:$time:${text.hashCode}");
    _msgBox.put(ChatMessageEntity(fromId: nodeId, text: text, timestamp: time, peerKey: toPeerId));
    p2p.sendToPeer(toPeerId, data);
  }

  List<Map<String, dynamic>> historyWith(String peerKey) {
    return (_msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)))
        .map((e) => {"from": e.fromId, "text": e.text, "time": e.timestamp})
        .toList();
  }

  void dispose() => _messageController.close();
}