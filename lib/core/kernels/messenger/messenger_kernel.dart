// lib/core/kernels/messenger/messenger_kernel.dart
import 'dart:async';
import '../../p2p/webrtc_engine.dart';
import '../../storage/objectbox/store.dart';
import '../../storage/entities/chat_message_entity.dart';
import '../../storage/entities/contact_entity.dart';
import '../../storage/friends/friend_request_store.dart';
import '../../../objectbox.g.dart';

class MessengerKernel {
  final String nodeId;
  final WebRTCNetworkEngine p2p;
  final ObjectBoxStore db;
  late final Box<ChatMessageEntity> _msgBox;
  late final Box<ContactEntity> _contactBox;

  /// État des demandes d'ami en attente (envoyées/reçues) — voir
  /// FriendRequestStore pour la limite technique sur le stockage.
  final FriendRequestStore friendRequests = FriendRequestStore();

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Émis à chaque changement d'état d'amitié (demande reçue, acceptée,
  /// refusée, annulée, ami supprimé) — l'UI (ChatProvider) s'y abonne
  /// pour rafraîchir listes de demandes/amis sans polling.
  final _friendEventsController = StreamController<void>.broadcast();
  Stream<void> get friendEvents => _friendEventsController.stream;

  final Set<String> _seenChatMessages = {};

  /// File d'attente des messages qui n'ont PAS pu être transmis
  /// immédiatement (pair hors ligne ou canal WebRTC encore en
  /// négociation). Sans cette file, `WebRTCNetworkEngine.sendToPeer`
  /// abandonnait silencieusement le message — l'UI l'affichait comme
  /// "envoyé" alors qu'il n'avait jamais quitté l'appareil. Chaque
  /// entrée est renvoyée automatiquement dès que le canal vers ce pair
  /// s'ouvre (voir `onPeerChannelOpen`, appelé par P2PNode). Sert aussi
  /// bien pour le chat que pour le protocole de demande d'ami.
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

  // ---------------- Amis : requêtes sortantes ----------------

  bool isFriend(String publicKey) =>
      _contactBox.query(ContactEntity_.publicKey.equals(publicKey)).build().findFirst() != null;

  List<ContactEntity> friends() => _contactBox.getAll()..sort((a, b) => a.name.compareTo(b.name));

  /// Envoie une demande d'ami — n'ajoute PAS le pair à mes contacts tout
  /// de suite : ça n'arrive qu'après acceptation explicite de l'autre
  /// côté (`_handleFriendAccept`), exactement comme les grandes
  /// messageries.
  Future<void> sendFriendRequest(String toPeerId, {String? name}) async {
    if (toPeerId == nodeId || isFriend(toPeerId)) return;
    await friendRequests.load();
    await friendRequests.addSent(toPeerId, name: name);
    _sendOrQueue(toPeerId, {
      "type": "friend_request",
      "from": nodeId,
      "name": name ?? "",
      "time": DateTime.now().toIso8601String(),
    });
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

  /// Suppression LOCALE UNIQUEMENT — comme WhatsApp/Telegram : retirer
  /// quelqu'un de mes contacts ne l'avertit pas et ne l'empêche pas de
  /// m'écrire. Aucun message réseau envoyé ici, volontairement.
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

  // ---------------- Amis : réception réseau ----------------

  Future<void> _handleFriendRequest(Map<String, dynamic> data) async {
    final fromId = data["from"] as String?;
    if (fromId == null || fromId == nodeId) return;
    await friendRequests.load();

    if (isFriend(fromId)) {
      // Déjà amis (ex: redemande après désync d'état) — je confirme
      // quand même pour que son état reparte propre de son côté.
      _sendOrQueue(fromId, {"type": "friend_accept", "from": nodeId, "time": DateTime.now().toIso8601String()});
      return;
    }

    final name = data["name"] as String?;

    if (friendRequests.hasSent(fromId)) {
      // Demande MUTUELLE : je lui avais déjà envoyé une demande avant de
      // recevoir la sienne. Comme les grandes messageries, on accepte
      // automatiquement des deux côtés plutôt que d'afficher une
      // demande en double qui n'aurait aucun sens à refuser.
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
    if (!friendRequests.hasSent(fromId)) return; // pas de demande en cours de mon côté — ignorer
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

  // ---------------- Chat ----------------

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
    _sendOrQueue(toPeerId, data);
  }

  /// Tente l'envoi immédiat ; si le canal n'est pas prêt (pair hors
  /// ligne ou négociation WebRTC en cours), met en file d'attente pour
  /// renvoi automatique dès la reconnexion — le message n'est JAMAIS
  /// perdu silencieusement tant que le pair finit par revenir en ligne.
  void _sendOrQueue(String toPeerId, Map<String, dynamic> data) {
    final delivered = p2p.sendToPeer(toPeerId, data);
    if (!delivered) {
      _outbox.putIfAbsent(toPeerId, () => []).add(data);
    }
  }

  /// À appeler par P2PNode dès que le canal WebRTC vers `peerId` s'ouvre
  /// (offre acceptée, connexion établie). Renvoie dans l'ordre tout ce
  /// qui attendait ce pair précisément.
  void onPeerChannelOpen(String peerId) {
    final pending = _outbox.remove(peerId);
    if (pending == null || pending.isEmpty) return;

    for (final data in pending) {
      final delivered = p2p.sendToPeer(peerId, data);
      if (!delivered) {
        // Le canal s'est refermé entre-temps : on remet en file pour la
        // prochaine ouverture au lieu de perdre le message.
        _outbox.putIfAbsent(peerId, () => []).add(data);
      }
    }
  }

  /// Nombre de messages en attente de renvoi pour ce pair (utile pour
  /// afficher un indicateur "en attente" côté UI si besoin).
  int pendingCountFor(String peerId) => _outbox[peerId]?.length ?? 0;

  List<Map<String, dynamic>> historyWith(String peerKey) {
    return (_msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)))
        .map((e) => {"from": e.fromId, "text": e.text, "time": e.timestamp})
        .toList();
  }

  /// Dernier message échangé avec ce pair (pour l'aperçu dans la liste
  /// des discussions), ou `null` s'il n'y a encore rien.
  Map<String, dynamic>? lastMessageWith(String peerKey) {
    final all = _msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().find();
    if (all.isEmpty) return null;
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final e = all.last;
    return {"from": e.fromId, "text": e.text, "time": e.timestamp};
  }

  /// Tous les pairs avec qui j'ai un historique de discussion, même
  /// s'ils ne sont pas (ou plus) dans mes contacts — comme WhatsApp qui
  /// garde une discussion visible avec un numéro non enregistré.
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
