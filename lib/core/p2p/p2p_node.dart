// lib/core/p2p/p2p_node.dart
import 'dart:async';
import '../storage/objectbox/store.dart';
import '../storage/repositories/tx_repository.dart';
import '../storage/repositories/order_repository.dart';
import '../storage/repositories/trade_repository.dart';
import '../storage/repositories/profile_repository.dart';
import '../utils/logger.dart';
import '../utils/node_identity.dart';
import '../dag/dag_engine.dart';
import '../consensus/consensus_engine.dart';
import '../wallet/wallet_core.dart';
import '../security/sybil_protection.dart';
import '../kernels/wallet/wallet_kernel.dart';
import '../kernels/messenger/messenger_kernel.dart';
import '../kernels/profile/profile_kernel.dart';
import '../kernels/market/market_kernel.dart';
import '../dag/transaction_model.dart';
import '../network/network_health.dart';
import 'webrtc_engine.dart';
import 'peer_manager.dart';
import 'signaling_client.dart';

class P2PNode {
  final NodeIdentityKeyPair identity;
  final String nodeId;
  late final WebRTCNetworkEngine p2p;
  late final PeerManager peerManager;
  late final NetworkHealth health;
  late final WalletKernel walletKernel;
  late final MessengerKernel messengerKernel;
  late final ProfileKernel profileKernel;
  late final MarketKernel marketKernel;
  late final ProfileRepository profileRepo;
  late final OrderRepository orderRepo;
  late final TradeRepository tradeRepo;

  final SybilProtection sybil = SybilProtection();

  SignalingClient? _signaling;
  bool isSignalingConnected = false;

  final _networkChangeController = StreamController<void>.broadcast();
  Stream<void> get networkChanges => _networkChangeController.stream;

  final _channelReadyController = StreamController<String>.broadcast();
  Stream<String> get onChannelReady => _channelReadyController.stream;

  final _signalingErrorController = StreamController<String>.broadcast();
  Stream<String> get signalingErrors => _signalingErrorController.stream;

  Timer? _healthTimer;
  final Map<String, DateTime> _lastOfferAt = {};
  final Map<String, int> _offerCountThisWindow = {};
  static const int _maxOffersPerSecond = 3;

  final Set<String> _pendingConnections = {};
  final Map<String, Timer> _connectionTimers = {};
  static const Duration _connectionTimeout = Duration(seconds: 30);

  P2PNode(this.identity, ObjectBoxStore db) : nodeId = identity.nodeId {
    p2p = WebRTCNetworkEngine(nodeId);
    peerManager = PeerManager(db, engine: p2p, sybil: sybil);
    health = NetworkHealth();

    p2p.onChannelOpen = (peerId) {
      Logger.info("P2PNode: Data channel open with $peerId");
      messengerKernel.onPeerChannelOpen(peerId);
      walletKernel.requestSync(peerId);
      profileKernel.announceTo(peerId);
      _connectionTimers[peerId]?.cancel();
      _connectionTimers.remove(peerId);
      _channelReadyController.add(peerId);
      _networkChangeController.add(null);
    };

    final dag = DagEngine();
    final consensus = ConsensusEngine();
    final walletCore = WalletCore();
    final txRepo = TxRepository(db);

    walletKernel = WalletKernel(
      identity: identity,
      dag: dag,
      consensus: consensus,
      wallet: walletCore,
      txRepo: txRepo,
      p2p: p2p,
      sybil: sybil,
    );

    messengerKernel = MessengerKernel(
      nodeId: nodeId,
      p2p: p2p,
      db: db,
    );

    profileRepo = ProfileRepository(db);
    profileKernel = ProfileKernel(
      nodeId: nodeId,
      p2p: p2p,
      repo: profileRepo,
      sybil: sybil,
    );

    orderRepo = OrderRepository(db);
    tradeRepo = TradeRepository(db);
    marketKernel = MarketKernel(identity: identity, p2p: p2p, orderRepo: orderRepo, tradeRepo: tradeRepo, dag: dag);
  }

  Stream<Map<String, dynamic>> get messages => messengerKernel.messages;
  Stream<void> get walletChanges => walletKernel.walletChanges;
  Stream<String> get profileChanges => profileKernel.profileChanges;
  DagEngine get dag => walletKernel.dag;
  WalletCore get wallet => walletKernel.wallet;

  Future<void> start({List<String>? signalingUrls}) async {
    await walletKernel.loadPersistedLedger();
    await messengerKernel.friendRequests.load();
    Logger.info("Starting P2P node: $nodeId");

    if (signalingUrls != null && signalingUrls.isNotEmpty) {
      _signaling = SignalingClient(signalingUrls);
      _signaling!.onConnect = () {
        isSignalingConnected = true;
        _signaling!.send({"type": "register", "id": nodeId});
        Logger.info("Signaling connected, registering...");
        _networkChangeController.add(null);
      };
      _signaling!.onRegistrationConfirmed = (id) {
        Logger.info("Signaling registration confirmed for $id");
      };
      _signaling!.onDisconnect = () {
        isSignalingConnected = false;
        Logger.warn("Signaling disconnected");
        _networkChangeController.add(null);
      };
      _signaling!.onMessage = (msg) {
        health.ping(nodeId);
        _handleSignal(msg);
      };

      p2p.onIceCandidate = (peerId, candidate) {
        _signaling?.send({
          "type": "ice",
          "to": peerId,
          "from": nodeId,
          "candidate": candidate,
        });
      };
    }

    health.ping(nodeId);
    _networkChangeController.add(null);

    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      health.ping(nodeId);
      _networkChangeController.add(null);
    });
  }

  void _handleSignal(Map<String, dynamic> msg) {
    final type = msg["type"] as String?;
    if (type == null) return;

    switch (type) {
      case "offer":
        _handleOffer(msg["from"], msg["sdp"]);
        break;
      case "answer":
        p2p.handleAnswer(msg["from"], msg["sdp"]);
        break;
      case "ice":
        p2p.handleIce(msg["from"], msg["candidate"]);
        break;
      case "registered":
        Logger.info("Signaling registration confirmed");
        break;
      case "error":
        final failedPeer = msg["peerId"] as String?;
        final errorMsg = msg["message"] as String? ?? "Erreur signaling inconnue";
        Logger.warn("Signaling error${failedPeer != null ? ' pour $failedPeer' : ''}: $errorMsg");
        _signalingErrorController.add(errorMsg);
        break;
      case "peer_list":
        final peers = List<String>.from(msg["peers"] ?? []);
        Logger.info("peer_list reçu (${peers.length} pairs)");
        for (final pid in peers) {
          if (pid != nodeId && !p2p.peers.containsKey(pid)) {
            if (nodeId.compareTo(pid) > 0) {
              Logger.info("Tie-break: Connecting to $pid");
              connectToPeer(pid);
            }
          }
        }
        break;
    }
  }

  bool _admitOffer(String peerId) {
    final now = DateTime.now();
    final last = _lastOfferAt[peerId];
    if (last == null || now.difference(last).inSeconds >= 1) {
      _lastOfferAt[peerId] = now;
      _offerCountThisWindow[peerId] = 0;
    }
    final count = (_offerCountThisWindow[peerId] ?? 0) + 1;
    _offerCountThisWindow[peerId] = count;
    if (count > _maxOffersPerSecond) {
      sybil.decreaseTrust(peerId);
      return false;
    }
    return true;
  }

  Future<void> _handleOffer(String peerId, dynamic sdp) async {
    if (peerManager.isBlocked(peerId)) return;
    if (!_admitOffer(peerId)) return;
    if (p2p.isConnectedTo(peerId)) return;

    _pendingConnections.remove(peerId);
    _pendingConnections.add(peerId);
    try {
      final answer = await p2p.acceptConnection(peerId, sdp);
      if (answer != null && _signaling != null) {
        _signaling!.send({
          "type": "answer",
          "to": peerId,
          "from": nodeId,
          "sdp": answer,
        });
      }
      peerManager.markNegotiating(peerId);
    } finally {
      _pendingConnections.remove(peerId);
    }
  }

  Future<void> connectToPeer(String peerId) async {
    if (peerManager.isBlocked(peerId)) return;
    if (_pendingConnections.contains(peerId)) return;
    if (p2p.isConnectedTo(peerId)) return;

    Logger.info("Connecting to peer $peerId...");
    _pendingConnections.add(peerId);
    _connectionTimers[peerId]?.cancel();
    _connectionTimers[peerId] = Timer(_connectionTimeout, () {
      if (!p2p.isPeerChannelOpen(peerId)) {
        Logger.warn("Connection to $peerId timed out after ${_connectionTimeout.inSeconds}s "
            "(isSignalingConnected=$isSignalingConnected) — offer/answer/ice ont pu être "
            "échangés mais le data channel WebRTC ne s'est jamais ouvert (NAT/TURN à vérifier). "
            "Tout message en attente pour ce pair (demande d'ami, chat) reste en file "
            "d'attente et repartira automatiquement à la prochaine connexion réussie.");
        // Régression corrigée : ce timeout supprimait le pair en silence total, sans
        // jamais prévenir l'UI. La demande d'ami envoyée pendant ce laps de temps
        // restait bloquée dans MessengerKernel._outbox sans qu'aucun message
        // n'explique pourquoi — d'où "invitation jamais reçue" sans la moindre erreur.
        _signalingErrorController.add(
          "Connexion vers ${peerId.length > 12 ? '${peerId.substring(0, 8)}…' : peerId} "
          "expirée après ${_connectionTimeout.inSeconds}s — le pair est probablement sur un "
          "autre réseau et injoignable directement.",
        );
        _pendingConnections.remove(peerId);
        _connectionTimers.remove(peerId);
        p2p.removePeer(peerId);
      }
    });
    try {
      final offer = await p2p.createOffer(peerId);
      if (offer != null && _signaling != null) {
        _signaling!.send({
          "type": "offer",
          "to": peerId,
          "from": nodeId,
          "sdp": offer,
        });
        peerManager.markNegotiating(peerId);
      }
    } finally {
      _pendingConnections.remove(peerId);
    }
  }

  Future<void> connectPeer(String addr) async {
    final peerId = addr.trim();
    if (peerId.isEmpty || peerId == nodeId) return;
    if (p2p.isPeerChannelOpen(peerId)) return;
    if (_signaling == null || !isSignalingConnected) {
       throw StateError("Signaling not connected");
    }
    await connectToPeer(peerId);
  }

  DagAcceptResult broadcastTx(Transaction tx) => walletKernel.broadcastTx(tx);
  void sendChat(String toPeerId, String text) => messengerKernel.sendPrivateChat(toPeerId, text);

  Stream<void> get friendEvents => messengerKernel.friendEvents;
  bool isFriend(String publicKey) => messengerKernel.isFriend(publicKey);
  Future<void> sendFriendRequest(String toPeerId, {String? name}) => messengerKernel.sendFriendRequest(toPeerId, name: name);
  Future<void> acceptFriendRequest(String fromPeerId) => messengerKernel.acceptFriendRequest(fromPeerId);
  Future<void> declineFriendRequest(String fromPeerId) => messengerKernel.declineFriendRequest(fromPeerId);
  Future<void> cancelFriendRequest(String toPeerId) => messengerKernel.cancelFriendRequest(toPeerId);
  void removeFriend(String publicKey) => messengerKernel.removeFriend(publicKey);
  Future<void> selfApprove(String txId) => walletKernel.selfApprove(txId);
  Future<void> broadcastMyProfile() => profileKernel.broadcastMine();

  void stop() {
    _healthTimer?.cancel();
    for (final t in _connectionTimers.values) { t.cancel(); }
    _connectionTimers.clear();
    p2p.dispose();
    _signaling?.close();
    walletKernel.dispose();
    messengerKernel.dispose();
    profileKernel.dispose();
    _networkChangeController.close();
    _channelReadyController.close();
    _signalingErrorController.close();
    marketKernel.dispose();
  }

  void reconnectSignaling() {
    if (_signaling == null) return;
    if (!isSignalingConnected) {
      _signaling!.retryNow();
    }
  }
}
