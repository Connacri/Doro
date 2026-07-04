import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';

class NetworkProvider extends ChangeNotifier {
  final P2PNode node;
  StreamSubscription<void>? _sub;

  NetworkProvider(this.node) {
    _sub = node.networkChanges.listen((_) => notifyListeners());
  }

  bool get isConnected => node.isSignalingConnected || peers.isNotEmpty;

  String get myId => node.nodeId;

  void init() {
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> connectPeer(String address) async {
    await node.connectPeer(address);
    notifyListeners();
  }

  List<String> get peers => node.p2p.peers.keys.toList();

  Future<void> stop() async {
    node.stop();
    notifyListeners();
  }
}
