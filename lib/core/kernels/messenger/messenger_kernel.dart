import 'dart:async';
import '../../p2p/webrtc_engine.dart';
import '../../utils/logger.dart';
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

  final Set<String> _contacts = {};

  MessengerKernel({
    required this.nodeId,
    required this.p2p,
    required this.db,
  }) {
    _msgBox = db.getBox<ChatMessageEntity>();
    _setupHandlers();
  }

  void _setupHandlers() {
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
    final text = data["text"] as String?;
    final time = data["time"] as String?;

    if (fromId == null || text == null || time == null) return;
    if (fromId == nodeId) return;

    final msgKey = "$fromId:$time:${text.hashCode}";
    if (_seenChatMessages.contains(msgKey)) return;
    _seenChatMessages.add(msgKey);

    _msgBox.put(ChatMessageEntity(fromId: fromId, text: text, timestamp: time));

    _messageController.add({"from": from, "data": data});

    p2p.broadcast(data);
  }

  void addContact(String publicKey) {
    _contacts.add(publicKey);
    Logger.info("Contact added: $publicKey");
  }

  void sendChat(String text) {
    final time = DateTime.now().toIso8601String();
    final data = {
      "type": "chat",
      "from": nodeId,
      "text": text,
      "time": time,
    };

    final msgKey = "$nodeId:$time:${text.hashCode}";
    _seenChatMessages.add(msgKey);

    _msgBox.put(ChatMessageEntity(fromId: nodeId, text: text, timestamp: time));

    p2p.broadcast(data);
  }

  List<Map<String, dynamic>> getHistory() {
    return _msgBox.getAll().map((e) => {
      "from": e.fromId,
      "text": e.text,
      "time": e.timestamp,
    }).toList();
  }

  void dispose() {
    _messageController.close();
  }
}
