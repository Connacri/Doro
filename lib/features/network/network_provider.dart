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

  /// Liste des pairs *réellement* connectés maintenant : `p2p.peers` est déjà
  /// une Map (clés uniques par construction, donc pas de doublon possible au
  /// niveau structure), mais on filtre en plus sur `isPeerChannelOpen` pour
  /// exclure tout pair resté enregistré alors que son data channel WebRTC
  /// s'est refermé entre-temps (évite d'afficher un pair "fantôme" comme
  /// s'il était encore joignable). Le tri par nom garde un ordre stable.
  List<String> get peers {
    final ids = node.p2p.peers.keys.where((id) => node.p2p.isPeerChannelOpen(id)).toSet().toList();
    ids.sort();
    return ids;
  }

  Future<void> stop() async {
    node.stop();
    notifyListeners();
  }
}
