import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/storage/entities/contact_entity.dart';
import '../../core/storage/friends/friend_request_store.dart';
import '../../core/storage/repositories/contact_repository.dart';
import '../wallet/wallet_provider.dart';

/// Aperçu d'une discussion pour la liste "Discussions" — comme l'écran
/// d'accueil de WhatsApp/Telegram : dernier message, heure, non-lus.
class ConversationPreview {
  final String peerId;
  final String name;
  final bool isFriend;
  final bool online;
  final String? lastMessage;
  final String? lastTime;
  final int unread;

  ConversationPreview({
    required this.peerId,
    required this.name,
    required this.isFriend,
    required this.online,
    this.lastMessage,
    this.lastTime,
    this.unread = 0,
  });
}

class ChatProvider extends ChangeNotifier {
  final P2PNode node;
  final ContactRepository contactRepo;
  WalletProvider? walletProvider;

  final Map<String, List<Map<String, dynamic>>> _conversations = {};
  final Map<String, int> _unread = {};
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _networkSub;
  StreamSubscription<String>? _channelSub;
  StreamSubscription<void>? _friendSub;
  StreamSubscription<String>? _sigErrSub;

  String? lastSignalingError;

  ChatProvider(this.node, this.contactRepo, {this.walletProvider}) {
    _sub = node.messages.listen((msg) {
      final data = msg["data"];
      if (data is Map) {
        final type = data["type"];
        if (type == "chat") {
          final peer = data["from"] == node.nodeId ? data["to"] : data["from"];
          if (peer is String) {
            messagesWith(peer).add(Map<String, dynamic>.from(data));
            if (peer != _activePeer) {
              _unread[peer] = (_unread[peer] ?? 0) + 1;
            }
            if (hasListeners) notifyListeners();
          }
        }
      }
    });

    _friendSub = node.friendEvents.listen((_) {
      if (hasListeners) notifyListeners();
    });

    _channelSub = node.onChannelReady.listen((_) {
      if (hasListeners) notifyListeners();
    });

    _networkSub = node.networkChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });

    _sigErrSub = node.signalingErrors.listen((err) {
      lastSignalingError = err;
      if (hasListeners) notifyListeners();
    });
  }

  String? _activePeer;
  /// À appeler par ChatScreen quand une discussion s'ouvre/se ferme —
  /// évite d'incrémenter le compteur de non-lus pour la conversation
  /// actuellement affichée à l'écran.
  void setActivePeer(String? peerId) {
    _activePeer = peerId;
    if (peerId != null) markRead(peerId);
  }

  void markRead(String peerId) {
    if (_unread.remove(peerId) != null) notifyListeners();
  }

  bool isOnline(String peerId) => node.p2p.peers.containsKey(peerId);
  String get myId => node.nodeId;

  // ---------------- Amis : listes ----------------

  List<ContactEntity> get friends => contactRepo.all();
  List<FriendRequest> get receivedRequests => node.messengerKernel.friendRequests.received();
  List<FriendRequest> get sentRequests => node.messengerKernel.friendRequests.sent();
  bool isFriend(String publicKey) => node.isFriend(publicKey);

  /// La liste "Discussions" : tous les amis + tout pair avec qui j'ai
  /// déjà échangé des messages (même sans lien d'amitié confirmé — comme
  /// une discussion WhatsApp avec un numéro non enregistré), triée par
  /// message le plus récent.
  List<ConversationPreview> get conversations {
    final peerIds = <String>{
      ...friends.map((c) => c.publicKey),
      ...node.messengerKernel.peersWithHistory(),
    };
    final list = peerIds.map((peerId) {
      final contact = friends.firstWhere((c) => c.publicKey == peerId, orElse: () => ContactEntity(publicKey: peerId, name: _shortId(peerId)));
      final last = node.messengerKernel.lastMessageWith(peerId);
      return ConversationPreview(
        peerId: peerId,
        name: contact.name,
        isFriend: isFriend(peerId),
        online: isOnline(peerId),
        lastMessage: last?["text"] as String?,
        lastTime: last?["time"] as String?,
        unread: _unread[peerId] ?? 0,
      );
    }).toList();
    list.sort((a, b) => (b.lastTime ?? '').compareTo(a.lastTime ?? ''));
    return list;
  }

  String _shortId(String key) => key.length > 14 ? "${key.substring(0, 8)}…${key.substring(key.length - 4)}" : key;

  // ---------------- Amis : actions ----------------

  /// Retourne `true` si la tentative de connexion a réussi (pair en
  /// ligne et canal ouvert), `false` si le pair n'est pas joignable
  /// pour l'instant (la demande partira dès qu'il reviendra en ligne).
  /// Lance une exception si une condition bloquante empêche l'envoi
  /// (signaling non connecté, etc.).
  Future<bool> sendFriendRequest(String publicKey, {String? name}) async {
    final key = publicKey.trim();
    if (key.isEmpty || key == node.nodeId) return false;
    await node.sendFriendRequest(key, name: name);
    if (isOnline(key)) return true;

    await node.connectPeer(key);
    notifyListeners();
    return p2pChannelOpen(key);
  }

  bool p2pChannelOpen(String peerId) => node.p2p.isPeerChannelOpen(peerId);

  void clearSignalingError() {
    lastSignalingError = null;
    notifyListeners();
  }

  Future<void> acceptRequest(String publicKey) async {
    await node.acceptFriendRequest(publicKey);
    notifyListeners();
  }

  Future<void> declineRequest(String publicKey) async {
    await node.declineFriendRequest(publicKey);
    notifyListeners();
  }

  Future<void> cancelRequest(String publicKey) async {
    await node.cancelFriendRequest(publicKey);
    notifyListeners();
  }

  void removeFriend(String publicKey) {
    node.removeFriend(publicKey);
    notifyListeners();
  }

  // ---------------- Chat ----------------

  List<Map<String, dynamic>> messagesWith(String peerId) =>
      _conversations.putIfAbsent(peerId, () => node.messengerKernel.historyWith(peerId));

  void send(String peerId, String text) {
    if (text.trim().isEmpty) return;
    messagesWith(peerId).add({
      "type": "chat",
      "from": node.nodeId,
      "to": peerId,
      "text": text,
      "time": DateTime.now().toIso8601String(),
    });
    notifyListeners();
    try {
      node.sendChat(peerId, text);
    } catch (_) {
      // Ne devrait plus arriver : MessengerKernel met le message en
      // file d'attente au lieu de le perdre si le pair est hors ligne.
    }
  }

  Future<bool> sendCrypto(String toAddress, BigInt amount) async {
    if (walletProvider == null || walletProvider!.wallets.isEmpty) return false;
    final txId = await walletProvider!.send(
      from: walletProvider!.wallets.last.address,
      to: toAddress,
      amount: amount,
    );
    if (txId != null) {
      messagesWith(toAddress).add({
        "type": "tx_info",
        "from": node.nodeId,
        "text": "💰 Envoi de ${(amount / BigInt.from(10).pow(18)).toStringAsFixed(2)} DORO",
        "time": DateTime.now().toIso8601String(),
      });
      notifyListeners();
    }
    return txId != null;
  }

  void clearHistory(String peerId) {
    _conversations.remove(peerId);
    node.messengerKernel.clearHistory(peerId);
    notifyListeners();
  }

  void clearAllHistory() {
    _conversations.clear();
    node.messengerKernel.clearAllHistory();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _networkSub?.cancel();
    _channelSub?.cancel();
    _friendSub?.cancel();
    _sigErrSub?.cancel();
    super.dispose();
  }
}
