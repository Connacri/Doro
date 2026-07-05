// lib/core/kernels/messenger/messenger_kernel.dart
import 'dart:async';
import '../../p2p/webrtc_engine.dart';
import '../../storage/objectbox/store.dart';
import '../../storage/entities/chat_message_entity.dart';
import '../../storage/entities/contact_entity.dart';
import '../../../objectbox.g.dart';

class MessengerKernel {
  final String nodeId;
  final WebRTCNetworkEngine p2p;
  final ObjectBoxStore db;
  late final Box<ChatMessageEntity> _msgBox;
  late final Box<ContactEntity> _contactBox;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final Set<String> _seenChatMessages = {};

  /// File d'attente des messages qui n'ont PAS pu être transmis
  /// immédiatement (pair hors ligne ou canal WebRTC encore en
  /// négociation). Sans cette file, `WebRTCNetworkEngine.sendToPeer`
  /// abandonnait silencieusement le message — l'UI l'affichait comme
  /// "envoyé" alors qu'il n'avait jamais quitté l'appareil. Chaque
  /// entrée est renvoyée automatiquement dès que le canal vers ce pair
  /// s'ouvre (voir `onPeerChannelOpen`, appelé par P2PNode).
  final Map<String, List<Map<String, dynamic>>> _outbox = {};

  MessengerKernel({required this.nodeId, required this.p2p, required this.db}) {
    _msgBox = db.getBox<ChatMessageEntity>();
    _contactBox = db.getBox<ContactEntity>();
    p2p.messages.listen((msg) {
      final data = msg.data;
      final from = msg.from;
      if (data is Map<String, dynamic>) {
        if (data["type"] == "chat") {
          _handleIncomingChat(from, data);
        } else if (data["type"] == "contact_invitation") {
          _handleIncomingInvitation(from, data);
        }
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
    if (toId != null && toId != nodeId) return;

    final msgKey = "$fromId:$time:${text.hashCode}";
    if (_seenChatMessages.contains(msgKey)) return;
    _seenChatMessages.add(msgKey);

    _msgBox.put(ChatMessageEntity(fromId: fromId, text: text, timestamp: time, peerKey: fromId));
    _messageController.add({"from": from, "data": data});
  }

  void _handleIncomingInvitation(String from, Map<String, dynamic> data) {
    final fromId = data["from"] as String?;
    if (fromId == null || fromId == nodeId) return;

    // Ajouter aux contacts si absent
    final existing = _contactBox.query(ContactEntity_.publicKey.equals(fromId)).build().findFirst();
    if (existing == null) {
      final name = fromId.length > 14 ? "${fromId.substring(0, 8)}…${fromId.substring(fromId.length - 4)}" : fromId;
      _contactBox.put(ContactEntity(publicKey: fromId, name: name));
    }

    // Message système
    final time = DateTime.now().toIso8601String();
    final inviteMsg = ChatMessageEntity(
      fromId: fromId,
      text: "👋 Vous a ajouté comme ami",
      timestamp: time,
      peerKey: fromId,
    );
    _msgBox.put(inviteMsg);

    _messageController.add({
      "from": from,
      "data": {
        "type": "contact_invitation",
        "from": fromId,
        "text": "👋 Vous a ajouté comme ami",
        "time": time,
      }
    });
  }

  void sendContactInvitation(String toPeerId) {
    final data = {
      "type": "contact_invitation",
      "from": nodeId,
      "to": toPeerId,
      "time": DateTime.now().toIso8601String(),
    };
    _sendOrQueue(toPeerId, data);
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

  void clearHistory(String peerKey) {
    _msgBox.query(ChatMessageEntity_.peerKey.equals(peerKey)).build().remove();
  }

  void clearAllHistory() {
    _msgBox.removeAll();
  }

  void dispose() => _messageController.close();
}
