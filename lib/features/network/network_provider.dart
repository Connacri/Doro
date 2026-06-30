import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/p2p/peer.dart';

class NetworkProvider extends ChangeNotifier {
  late P2PNode node;

  bool isConnected = false;

  void init(String nodeId) {
    node = P2PNode(nodeId);
    isConnected = true;
    notifyListeners();
  }

  void addPeer(String id, String address) {
    node.addPeer(Peer(id: id, address: address));
    notifyListeners();
  }

  void broadcast(Map<String, dynamic> msg) {
    node.broadcast(msg);
  }
}