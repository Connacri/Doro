// lib/features/chat/chat_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/supabase/supabase_bootstrap.dart';
import '../../core/kernels/messenger/supabase_messenger_kernel.dart';
import '../../core/supabase/presence_service.dart';
import '../../core/storage/entities/contact_entity.dart';
import '../../core/storage/friends/friend_request_store.dart' show FriendRequest;
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

/// Pilote la messagerie Supabase. Ne dépend PAS directement d'un
/// kernel prêt à la construction : s'abonne au [SupabaseBootstrap] et
/// se (re)branche dès que `messenger`/`presence` deviennent
/// disponibles. Tant que ce n'est pas le cas, [available] est `false`
/// et toutes les actions sont des no-ops silencieux — c'est à l'UI
/// (chats_screen.dart notamment) d'afficher un état "indisponible" +
/// bouton "Réessayer" plutôt que de bloquer toute l'app.
class ChatProvider extends ChangeNotifier {
  final SupabaseBootstrap bootstrap;
  WalletProvider? walletProvider;

  SupabaseMessengerKernel? _messenger;
  PresenceService? _presence;
  bool get available => _messenger != null && _presence != null;
  String? get unavailableReason => bootstrap.errorMessage;

  final Map<String, List<Map<String, dynamic>>> _conversations = {};
  final Map<String, int> _unread = {};
  final Set<String> _typingPeers = {};

  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _friendSub;
  StreamSubscription<Set<String>>? _presenceSub;
  StreamSubscription<({String peer, bool typing})>? _typingSub;

  Set<String> _onlinePeers = {};
  String? _activePeer;

  ChatProvider(this.bootstrap, {this.walletProvider}) {
    bootstrap.addListener(_onBootstrapChange);
    _onBootstrapChange(); // au cas où déjà prêt au moment de la création
  }

  void _onBootstrapChange() {
    final newMessenger = bootstrap.messenger;
    final newPresence = bootstrap.presence;
    if (newMessenger == _messenger && newPresence == _presence) {
      // Rien de nouveau côté kernel (juste un changement d'état
      // initializing/error) : on notifie quand même pour que l'UI
      // affiche l'état à jour (spinner, message d'erreur, etc.).
      notifyListeners();
      return;
    }
    _unbind();
    _messenger = newMessenger;
    _presence = newPresence;
    if (_messenger != null && _presence != null) {
      _bind(_messenger!, _presence!);
    }
    notifyListeners();
  }

  void _bind(SupabaseMessengerKernel messenger, PresenceService presence) {
    _sub = messenger.messages.listen((msg) {
      final data = msg["data"];
      if (data is Map) {
        final peer = data["from"] == messenger.nodeId ? data["to"] : data["from"];
        if (peer is String) {
          final list = messagesWith(peer);
          final time = data["time"] as String?;
          final existingIndex = time == null ? -1 : list.indexWhere((m) => m["time"] == time);
          if (existingIndex >= 0) {
            list[existingIndex] = Map<String, dynamic>.from(data);
          } else {
            list.add(Map<String, dynamic>.from(data));
          }
          if (peer != _activePeer && data["from"] != messenger.nodeId) {
            _unread[peer] = (_unread[peer] ?? 0) + 1;
          } else if (peer == _activePeer && data["from"] != messenger.nodeId) {
            sendReadReceipt(peer);
          }
          if (hasListeners) notifyListeners();
        }
      }
    });

    _friendSub = messenger.friendEvents.listen((_) {
      if (hasListeners) notifyListeners();
    });

    _presenceSub = presence.onlinePeers.listen((peers) {
      _onlinePeers = peers;
      if (hasListeners) notifyListeners();
    });

    _typingSub = presence.typingEvents.listen((event) {
      if (event.typing) {
        _typingPeers.add(event.peer);
      } else {
        _typingPeers.remove(event.peer);
      }
      if (hasListeners) notifyListeners();
    });
  }

  void _unbind() {
    _sub?.cancel();
    _friendSub?.cancel();
    _presenceSub?.cancel();
    _typingSub?.cancel();
    _sub = null;
    _friendSub = null;
    _presenceSub = null;
    _typingSub = null;
  }

  void setActivePeer(String? peerId) {
    _activePeer = peerId;
    final messenger = _messenger;
    if (peerId != null && messenger != null) {
      markRead(peerId);
      sendReadReceipt(peerId);
      messenger.syncHistoryWith(peerId).then((_) {
        _conversations[peerId] = messenger.historyWith(peerId);
        if (hasListeners) notifyListeners();
      });
    }
  }

  void sendReadReceipt(String peerId) {
    final messenger = _messenger;
    if (messenger == null) return;
    final list = messagesWith(peerId);
    if (list.isEmpty) return;
    String? lastReceivedTime;
    for (final m in list.reversed) {
      if (m["from"] == peerId) {
        lastReceivedTime = m["time"] as String?;
        break;
      }
    }
    if (lastReceivedTime != null) {
      messenger.sendChatReadConfirmation(peerId, lastReceivedTime);
    }
  }

  void markRead(String peerId) {
    if (_unread.remove(peerId) != null) notifyListeners();
  }

  bool isOnline(String peerId) => _onlinePeers.contains(peerId);
  bool isTyping(String peerId) => _typingPeers.contains(peerId);
  void sendTyping(String peerId, bool typing) => _presence?.sendTyping(peerId, typing);
  String? get myId => _messenger?.nodeId;

  // ---------------- Amis : listes ----------------

  List<ContactEntity> get friends => _messenger?.friends() ?? const [];
  List<FriendRequest> get receivedRequests => _messenger?.receivedRequests() ?? const [];
  List<FriendRequest> get sentRequests => _messenger?.sentRequests() ?? const [];
  bool isFriend(String publicKey) => _messenger?.isFriend(publicKey) ?? false;

  /// La liste "Discussions" : tous les amis + tout pair avec qui j'ai
  /// déjà échangé des messages, triée par message le plus récent.
  List<ConversationPreview> get conversations {
    final messenger = _messenger;
    if (messenger == null) return const [];
    final peerIds = <String>{
      ...friends.map((c) => c.publicKey),
      ...messenger.peersWithHistory(),
    };
    final list = peerIds.map((peerId) {
      final contact = friends.firstWhere((c) => c.publicKey == peerId,
          orElse: () => ContactEntity(publicKey: peerId, name: _shortId(peerId)));
      final last = messenger.lastMessageWith(peerId);
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

  Future<bool> sendFriendRequest(String publicKey, {String? name}) async {
    final messenger = _messenger;
    if (messenger == null) return false;
    final key = publicKey.trim();
    if (key.isEmpty || key == messenger.nodeId) return false;
    await messenger.sendFriendRequest(key, name: name);
    notifyListeners();
    return true;
  }

  Future<void> acceptRequest(String publicKey) async {
    final messenger = _messenger;
    if (messenger == null) return;
    await messenger.acceptFriendRequest(publicKey);
    notifyListeners();
  }

  Future<void> declineRequest(String publicKey) async {
    final messenger = _messenger;
    if (messenger == null) return;
    await messenger.declineFriendRequest(publicKey);
    notifyListeners();
  }

  Future<void> cancelRequest(String publicKey) async {
    final messenger = _messenger;
    if (messenger == null) return;
    await messenger.cancelFriendRequest(publicKey);
    notifyListeners();
  }

  Future<void> removeFriend(String publicKey) async {
    final messenger = _messenger;
    if (messenger == null) return;
    await messenger.removeFriend(publicKey);
    notifyListeners();
  }

  // ---------------- Chat ----------------

  List<Map<String, dynamic>> messagesWith(String peerId) =>
      _conversations.putIfAbsent(peerId, () => _messenger?.historyWith(peerId) ?? []);

  void send(String peerId, String text) {
    final messenger = _messenger;
    if (messenger == null || text.trim().isEmpty) return;
    messagesWith(peerId).add({
      "type": "chat",
      "from": messenger.nodeId,
      "to": peerId,
      "text": text,
      "time": DateTime.now().toIso8601String(),
      "status": "sent",
    });
    notifyListeners();
    messenger.sendPrivateChat(peerId, text);
  }

  /// Annule l'envoi d'un message pour tout le monde (comme WhatsApp/
  /// Telegram), dans la fenêtre autorisée par le serveur (2h). Renvoie
  /// `false` si le message est trop ancien ou n'appartient pas à
  /// l'utilisateur.
  Future<bool> unsend(String peerId, String timestamp) async {
    final messenger = _messenger;
    if (messenger == null) return false;
    final id = messenger.messageIdFor(peerId, timestamp);
    if (id == null) return false;
    final ok = await messenger.unsendMessage(id);
    if (ok) {
      final list = messagesWith(peerId);
      final idx = list.indexWhere((m) => m["time"] == timestamp);
      if (idx >= 0) {
        list[idx] = {...list[idx], "text": "", "status": "deleted"};
        notifyListeners();
      }
    }
    return ok;
  }

  Future<bool> sendCrypto(String toAddress, BigInt amount) async {
    final messenger = _messenger;
    if (messenger == null || walletProvider == null || walletProvider!.wallets.isEmpty) return false;
    final txId = await walletProvider!.send(
      from: walletProvider!.wallets.last.address,
      to: toAddress,
      amount: amount,
    );
    if (txId != null) {
      messagesWith(toAddress).add({
        "type": "tx_info",
        "from": messenger.nodeId,
        "text": "💰 Envoi de ${(amount / BigInt.from(10).pow(18)).toStringAsFixed(2)} DORO",
        "time": DateTime.now().toIso8601String(),
      });
      notifyListeners();
    }
    return txId != null;
  }

  /// Vide la discussion "pour moi" uniquement (comme WhatsApp "Effacer
  /// la discussion") — n'affecte pas l'historique de l'autre pair.
  void clearHistory(String peerId) {
    _conversations.remove(peerId);
    _messenger?.clearConversationForMeOnServer(peerId);
    notifyListeners();
  }

  void clearAllHistory() {
    final messenger = _messenger;
    if (messenger == null) return;
    for (final peerId in {...friends.map((c) => c.publicKey), ...messenger.peersWithHistory()}) {
      messenger.clearConversationForMeOnServer(peerId);
    }
    _conversations.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    bootstrap.removeListener(_onBootstrapChange);
    _unbind();
    super.dispose();
  }
}
