import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';
import '../wallet/wallet_provider.dart';

class ChatProvider extends ChangeNotifier {
  final P2PNode node;
  final WalletProvider? walletProvider;

  final List<Map<String, dynamic>> messages = [];

  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<void>? _networkSub;

  ChatProvider(this.node, {this.walletProvider}) {
    // Load history
    messages.addAll(node.messengerKernel.getHistory());

    _sub = node.messages.listen((msg) {
      final data = msg["data"];

      if (data is Map && data["type"] == "chat") {
        messages.add(Map<String, dynamic>.from(data));

        if (hasListeners) {
          notifyListeners();
        }
      } else if (data is Map && data["type"] == "tx_info") {
        messages.add(Map<String, dynamic>.from(data));
        if (hasListeners) notifyListeners();
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

  Future<void> addContact(String publicKey) async {
    node.messengerKernel.addContact(publicKey);
    try {
      await node.connectPeer(publicKey);
    } catch (e) {
    }
    notifyListeners();
  }

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

  Future<bool> sendCrypto(String toAddress, BigInt amount) async {
    if (walletProvider == null) return false;

    final wallets = walletProvider!.wallets;
    if (wallets.isEmpty) return false;

    final ok = await walletProvider!.send(
      from: wallets.first.address,
      to: toAddress,
      amount: amount,
    );

    if (ok) {
      // Local info message
      messages.add({
        "type": "tx_info",
        "from": node.nodeId,
        "text": "💰 Envoi de ${(amount / BigInt.from(10).pow(18)).toStringAsFixed(2)} DORO à $toAddress",
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
