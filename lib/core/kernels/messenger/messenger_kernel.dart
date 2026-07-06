// lib/core/kernels/messenger/messenger_kernel.dart
import 'dart:async';
import '../../p2p/webrtc_engine.dart';
import '../../storage/objectbox/store.dart';
import '../../storage/entities/chat_message_entity.dart';
import '../../storage/entities/contact_entity.dart';
import '../../storage/friends/friend_request_store.dart';
import '../../../objectbox.g.dart';
import '../../utils/logger.dart';

class MessengerKernel {
  final String nodeId;
  final WebRTCNetworkEngine p2p;
  final ObjectBoxStore db;
  late final Box<ChatMessageEntity> _msgBox;
  late final Box<ContactEntity> _contactBox;

  final FriendRequestStore friendRequests = FriendRequestStore();

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final _friendEventsController = StreamController<void>.broadcast();
  Stream<void> get friendEvents => _friendEventsController.stream;

  final Set<String> _seenChatMessages = {};
  final Map<String, List<Map<String, dynamic>>> _outbox = {};

  MessengerKernel({required this.nodeId, required this.p2p, required this.db}) {
    _msgBox = db.getBox<ChatMessageEntity>();
    _contactBox = db.getBox<ContactEntity>();
    friendRequests.load();
    p2p.messages.listen((msg) {
      final data = msg.data;
      final from = msg.from;
      if (data is Map<String, dynamic>) {
        switch (data["type"]) {
          case "chat":
            _handleIncomingChat(from, data);
            break;
          case "friend_request":
            _handleFriendRequest(data);
            break;
          case "friend_accept":
            _handleFriendAccept(data);
            break;
          case "friend_decline":
            _handleFriendDecline(data);
            break;
          case "friend_cancel":
            _handleFriendCancel(data);
            break;
        }
      }
    });
  }

  bool isFriend(String publicKey) =>
      _contactBox.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst() != null;

  List<ContactEntity> friends() => _contactBox.getAll()..sort((a, b) => a.name.compareTo(b.name));

  Future<void> sendFriendRequest(String toPeerId, {String? name}) async {
    if (toPeerId == nodeId || isFriend(toPeerId)) return;
    await friendRequests.load();
    await friendRequests.addSent(toPeerId, name: name);

    final payload = {
      "type": "friend_request",
      "from": nodeId,
      "name": name ?? "",
      "time": DateTime.now().toIso8601String(),
    };

    Logger.info("MessengerKernel: Sending friend request to $toPeerId");
    _sendOrQueue(toPeerId, payload);
    _friendEventsController.add(null);
  }

  Future<void> acceptFriendRequest(String fromPeerId) async {
    await friendRequests.load();
    final storedName = friendRequests.nameOf(fromPeerId);
    await friendRequests.remove(fromPeerId);
    _addAsFriend(fromPeerId, name: storedName);
    _sendOrQueue(fromPeerId, {"type": "friend_accept", "from": nodeId, "time": DateTime.now().toIso8601String()});
    _friendEventsController.add(null);
  }

  Future<void> declineFriendRequest(String fromPeerId) async {
    await friendRequests.remove(fromPeerId);
    _sendOrQueue(fromPeerId, {"type": "friend_decline", "from": nodeId, "time": DateTime.now().toIso8601String()});
    _friendEventsController.add(null);
  }

  Future<void> cancelFriendRequest(String toPeerId) async {
    await friendRequests.remove(toPeerId);
    _sendOrQueue(toPeerId, {"type": "friend_cancel", "from": nodeId, "time": DateTime.now().toIso8601String()});
    _friendEventsController.add(null);
  }

  void removeFriend(String publicKey) {
    final existing = _contactBox.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst();
    if (existing != null) _contactBox.remove(existing.id);
    _friendEventsController.add(null);
  }

  void _addAsFriend(String peerId, {String? name}) {
    final existing = _contactBox.query(ContactEntity_.publicKey.equals(peerId)).build().findFirst();
    if (existing != null) return;
    final displayName = (name != null && name.isNotEmpty) ? name : _shortId(peerId);
    _contactBox.put(ContactEntity(publicKey: peerId, name: displayName));
  }

  Future<void> _handleFriendRequest(Map<String, dynamic> data) async {
    final fromId = data["from"] as String?;
    if (fromId == null || fromId == nodeId) return;
    await friendRequests.load();

    Logger.info("MessengerKernel: Received friend request from $fromId");

    if (isFriend(fromId)) {
      _sendOrQueue(fromId, {"type": "friend_accept", "from": nodeId, "time": DateTime.now().toIso8601String()});
      return;
    }

    final name = data["name"] as String?;

    if (friendRequests.hasSent(fromId)) {
      await friendRequests.remove(fromId);
      _addAsFriend(fromId, name: (name != null && name.isNotEmpty) ? name : null);
      _sendOrQueue(fromId, {"type": "friend_accept", "from": nodeId, "time": DateTime.now().toIso8601String()});
      _friendEventsController.add(null);
      return;
    }

    await friendRequests.addReceived(fromId, name: (name != null && name.isNotEmpty) ? name : null);
    _friendEventsController.add(null);
  }

  Future<void> _handleFriendAccept(Map<String, dynamic> data) async {
    final fromId = data["from"] as String?;
    if (fromId == null) return;
    await friendRequests.load();
    Logger.info("MessengerKernel: Friend request accepted by $fromId");
    if (!friendRequests.hasSent(fromId)) return;
    final storedName = friendRequests.nameOf(fromId);
    await friendRequests.remove(fromId);
    _addAsFriend(fromId, name: storedName);
    _friendEventsController.add(null);
  }

  Future<void> _handleFriendDecline(Map<String, dynamic> data) async {
    final fromId = data["from"] as String?;
    if (fromId == null) return;
    await friendRequests.remove(fromId);
    _friendEventsController.add(null);
  }

  Future<void> _handleFriendCancel(Map<String, dynamic> data) async {
    final fromId = data["from"] as String?;
    if (fromId == null) return;
    await friendRequests.remove(fromId);
    _friendEventsController.add(null);
  }

  void _handleIncomingChat(String from, Map<String, dynamic> data) {
    final fromId = data["from"] as String?;
    final toId = data["to"] as String?;
    final text = data["text"] as String?;
    final time = data["time"] as String?;
    if (fromId == null || text == null || time == null) return;
    if (fromId == nodeId) return;
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

    Logger.info("MessengerKernel: Sending private chat to $toPeerId");
    _sendOrQueue(toPeerId, data);
  }

  void _sendOrQueue(String toPeerId, Map<String, dynamic> data) {
    final delivered = p2p.sendToPeer(toPeerId, data);
    if (!delivered) {
      Logger.info("MessengerKernel: Peer $toPeerId not ready, queuing message (type: ${data['type']})");
      _outbox.putIfAbsent(toPeerId, () => []).add(data);
    } else {
      Logger.info("MessengerKernel: Message delivered to $toPeerId (type: ${data['type']})");
    }
  }

  void onPeerChannelOpen(String peerId) {
    final pending = _outbox.remove(peerId);
    if (pending == null || pending.isEmpty) return;

    Logger.info("MessengerKernel: Flushing ${pending.length} pending messages for $peerId");
    for (final data in pending) {
      final delivered = p2p.sendToPeer(peerId, data);
      if (!delivered) {
        _outbox.putIfAbsent(peerId, () => []).add(data);
      }
    }
  }

  int pendingCountFor(String peerId) => _outbox[peerId]?.length ?? 0;

  List<Map<String, dynamic>> historyWith(String peerKey) {
    return (_msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)))
        .map((e) => {"from": e.fromId, "text": e.text, "time": e.timestamp})
        .toList();
  }

  Map<String, dynamic>? lastMessageWith(String peerKey) {
    final all = _msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find();
    if (all.isEmpty) return null;
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final e = all.last;
    return {"from": e.fromId, "text": e.text, "time": e.timestamp};
  }

  Set<String> peersWithHistory() {
    return _msgBox.getAll().map((e) => e.peerKey).toSet();
  }

  void clearHistory(String peerKey) {
    _msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().remove();
  }

  void clearAllHistory() {
    _msgBox.removeAll();
  }

  String _shortId(String key) =>
      key.length > 14 ? "${key.substring(0, 8)}…${key.substring(key.length - 4)}" : key;

  void dispose() {
    _messageController.close();
    _friendEventsController.close();
  }
}
