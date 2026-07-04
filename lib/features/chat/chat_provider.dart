// lib/features/chat/chat_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/storage/entities/contact_entity.dart';
import '../../core/storage/repositories/contact_repository.dart';
import '../wallet/wallet_provider.dart';

class ChatProvider extends ChangeNotifier {
  final P2PNode node;
  final ContactRepository contactRepo;
  final WalletProvider? walletProvider;

  final Map<String, List<Map<String, dynamic>>> _conversations = {};
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _networkSub;

  ChatProvider(this.node, this.contactRepo, {this.walletProvider}) {
    _sub = node.messages.listen((msg) {
      final data = msg["data"];
      if (data is Map && data["type"] == "chat") {
        final peer = data["from"] == node.nodeId ? data["to"] : data["from"];
        if (peer is String) {
          messagesWith(peer).add(Map<String, dynamic>.from(data));
          if (hasListeners) notifyListeners();
        }
      }
    });
    _networkSub = node.networkChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
  }

  List<ContactEntity> get contacts => contactRepo.all();
  bool isOnline(String peerId) => node.p2p.peers.containsKey(peerId);
  String get myId => node.nodeId;

  List<Map<String, dynamic>> messagesWith(String peerId) =>
      _conversations.putIfAbsent(peerId, () => node.messengerKernel.historyWith(peerId));

  Future<void> addContact(String publicKey, {String? name}) async {
    final key = publicKey.trim();
    if (key.isEmpty || key == node.nodeId) return;
    contactRepo.add(key, name: name);
    try {
      await node.connectPeer(key);
    } catch (_) {
      // Pas grave si offline : la connexion se refera à l'ouverture du chat.
    }
    notifyListeners();
  }

  void removeContact(String publicKey) {
    contactRepo.remove(publicKey);
    _conversations.remove(publicKey);
    notifyListeners();
  }

  void send(String peerId, String text) {
    if (text.trim().isEmpty) return;
    node.sendChat(peerId, text);
    messagesWith(peerId).add({
      "from": node.nodeId,
      "to": peerId,
      "text": text,
      "time": DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  Future<bool> sendCrypto(String toAddress, BigInt amount) async {
    if (walletProvider == null || walletProvider!.wallets.isEmpty) return false;
    final ok = await walletProvider!.send(
      from: walletProvider!.wallets.first.address,
      to: toAddress,
      amount: amount,
    );
    if (ok) {
      messagesWith(toAddress).add({
        "type": "tx_info",
        "from": node.nodeId,
        "text": "💰 Envoi de ${(amount / BigInt.from(10).pow(18)).toStringAsFixed(2)} DORO",
        "time": DateTime.now().toIso8601String(),
      });
      notifyListeners();
    }
    return ok;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _networkSub?.cancel();
    super.dispose();
  }
}