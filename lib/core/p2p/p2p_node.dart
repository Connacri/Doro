import 'dart:async';
import 'dart:convert';

import '../crypto/signature.dart';
import '../gossip/gossip_engine.dart';
import '../dag/dag_engine.dart';
import '../sync/sync_engine.dart';
import '../consensus/consensus_engine.dart';
import '../consensus/reputation_score.dart';
import '../wallet/wallet_core.dart';
import '../network/network_health.dart';
import '../utils/logger.dart';
import 'peer_model.dart';
import 'webrtc_engine.dart';
import 'signaling_client.dart';
import 'peer_manager.dart';

class P2PNode {
  final String nodeId;
  late final CryptoService crypto;
  late final WebRTCNetworkEngine p2p;
  late final GossipEngine gossip;
  late final DagEngine dag;
  late final SyncEngine sync;
  late final ConsensusEngine consensus;
  late final WalletCore wallet;
  late final NetworkHealth health;
  late final PeerManager peerManager;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  SignalingClient? _signaling;

  P2PNode(this.nodeId) {
    crypto = CryptoService();
    p2p = WebRTCNetworkEngine();
    gossip = GossipEngine();
    dag = DagEngine();
    sync = SyncEngine();
    consensus = ConsensusEngine(ReputationScore());
    wallet = WalletCore();
    health = NetworkHealth();
    peerManager = PeerManager(engine: p2p);

    _wire();
  }

  void _wire() {
    p2p.onMessage = (from, msg) {
      try {
        final data = jsonDecode(msg);
        _messageController.add({"from": from, "data": data});

        // NB: gossip.receive()/onBroadcast était câblé ici auparavant mais
        // enveloppait les données dans {"from":..,"payload": raw}, donc
        // data["type"] ne valait jamais "tx" et le DAG ne recevait jamais
        // les transactions reçues du réseau. On route directement depuis
        // le message décodé.
        if (data is Map && data["type"] == "tx") {
          dag.addFromNetwork(Map<String, dynamic>.from(data));
        }
      } catch (e) {
        Logger.error("Failed to process message from $from: $e");
      }
    };

    dag.onCommit = (tx) {
      sync.push(tx);
    };
  }

  Future<void> start({String? signalingUrl}) async {
    Logger.info("Starting P2P node: $nodeId");

    await crypto.generateKeyPair();
    Logger.info("Node identity generated");

    if (signalingUrl != null) {
      _signaling = SignalingClient(signalingUrl);
      _signaling!.onMessage = (msg) {
        _handleSignal(msg);
      };
      _signaling!.send({"type": "register", "id": nodeId});
      Logger.info("Connected to signaling server: $signalingUrl");
    }

    health.ping(nodeId);
  }

  void _handleSignal(Map<String, dynamic> msg) {
    final type = msg["type"] as String?;
    if (type == null) return;

    switch (type) {
      case "peer_offer":
        final peerId = msg["from"] as String;
        final sdp = msg["sdp"];
        _handleOffer(peerId, sdp);
        break;
      case "peer_answer":
        final peerId = msg["from"] as String;
        final sdp = msg["sdp"];
        _handleAnswer(peerId, sdp);
        break;
      case "peer_ice":
        final peerId = msg["from"] as String;
        final candidate = msg["candidate"];
        _handleIce(peerId, candidate);
        break;
      case "peer_list":
        final peers = List<String>.from(msg["peers"] ?? []);
        for (final pid in peers) {
          if (pid != nodeId && !p2p.peers.containsKey(pid)) {
            connectToPeer(pid);
          }
        }
        break;
    }
  }

  Future<void> _handleOffer(String peerId, dynamic sdp) async {
    await p2p.acceptConnection(peerId, sdp);
    peerManager.registerPeer(Peer(id: peerId, address: "", lastSeen: DateTime.now()));
    health.ping(peerId);
  }

  Future<void> _handleAnswer(String peerId, dynamic sdp) async {
    await p2p.handleAnswer(peerId, sdp);
    health.ping(peerId);
  }

  Future<void> _handleIce(String peerId, dynamic candidate) async {
    await p2p.handleIce(peerId, candidate);
  }

  Future<void> connectToPeer(String peerId) async {
    final offer = await p2p.createOffer(peerId);
    if (offer != null && _signaling != null) {
      _signaling!.send({
        "type": "offer",
        "to": peerId,
        "from": nodeId,
        "sdp": offer,
      });
      peerManager.registerPeer(Peer(id: peerId, address: "", lastSeen: DateTime.now()));
    }
  }

  Future<void> connectPeer(String addr) async {
    final peer = Peer(id: addr, address: addr, lastSeen: DateTime.now());
    await peerManager.addPeer(peer);
  }

  void broadcastTx(Map<String, dynamic> txData) {
    // Commit local d'abord (dedup naturel via l'id dans DagEngine.ledger),
    // pour que l'expéditeur voie sa propre transaction dans son Ledger
    // même s'il est temporairement seul sur le réseau.
    dag.addFromNetwork(txData);
    p2p.broadcast({"type": "tx", ...txData});
  }

  void sendChat(String text) {
    p2p.broadcast({
      "type": "chat",
      "from": nodeId,
      "text": text,
      "time": DateTime.now().toIso8601String(),
    });
  }

  Future<void> stop() async {
    await p2p.dispose();
    _signaling?.close();
    await _messageController.close();
    Logger.info("P2P node $nodeId stopped");
  }
}