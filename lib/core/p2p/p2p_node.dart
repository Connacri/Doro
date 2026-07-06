import 'dart:async';
import '../kernels/wallet/wallet_kernel.dart';
import '../kernels/messenger/messenger_kernel.dart';
import '../dag/dag_engine.dart';
import '../dag/transaction_model.dart';
import '../consensus/consensus_engine.dart';
import '../wallet/wallet_core.dart';
import '../network/network_health.dart';
import '../storage/objectbox/store.dart';
import '../storage/repositories/tx_repository.dart';
import '../utils/logger.dart';
import '../utils/node_identity.dart';
import 'peer_model.dart';
import 'webrtc_engine.dart';
import 'signaling_client.dart';
import 'peer_manager.dart';
import '../kernels/market/market_kernel.dart';
import '../storage/repositories/order_repository.dart';
import '../storage/repositories/trade_repository.dart';
import '../security/sybil_protection.dart';

class P2PNode {
  final String nodeId;
  final NodeIdentityKeyPair identity;

  late final WebRTCNetworkEngine p2p;
  SignalingClient? _signaling;
  late final PeerManager peerManager;
  late final NetworkHealth health;

  late final WalletKernel walletKernel;
  late final MessengerKernel messengerKernel;

  final _networkChangeController = StreamController<void>.broadcast();
  Stream<void> get networkChanges => _networkChangeController.stream;

  final _channelReadyController = StreamController<String>.broadcast();
  Stream<String> get onChannelReady => _channelReadyController.stream;

  bool isSignalingConnected = false;
  Timer? _healthTimer;

  late final MarketKernel marketKernel;
  late final OrderRepository orderRepo;
  late final TradeRepository tradeRepo;

  /// Une seule instance partagée entre la couche connexion (`PeerManager`)
  /// et la couche wallet (`WalletKernel`) — un pair pénalisé pour avoir
  /// envoyé une tx forgée doit aussi être bloqué au niveau connexion, et
  /// inversement. Deux instances séparées créeraient deux "vérités" sur la
  /// confiance d'un même pair, l'une pouvant l'autoriser pendant que
  /// l'autre le bannit.
  final SybilProtection sybil = SybilProtection();

  /// Limite le nombre d'offres WebRTC entrantes traitées par pair et par
  /// seconde — sans ça, un pair (ou un faux pair usurpant plusieurs
  /// `nodeId`) peut saturer le CPU de négociation ICE en boucle.
  final Map<String, DateTime> _lastOfferAt = {};
  final Map<String, int> _offerCountThisWindow = {};
  static const int _maxOffersPerSecond = 3;

  /// Évite la double connexion : quand les deux pairs reçoivent
  /// `peer_list` simultanément, chacun tente d'initier ET de répondre
  /// pour la même paire, ce qui crée deux `PeerConnection` dont l'une
  /// écrase l'autre dans le map — canaux instables, messages perdus.
  final Set<String> _pendingConnections = {};

  P2PNode(this.identity, ObjectBoxStore db) : nodeId = identity.nodeId {
    p2p = WebRTCNetworkEngine(nodeId);
    peerManager = PeerManager(db, engine: p2p, sybil: sybil);
    health = NetworkHealth();

    p2p.onChannelOpen = (peerId) {
      // Le canal vient de s'ouvrir : tout message de chat/invitation qui
      // attendait ce pair précisément peut maintenant partir pour de
      // vrai (voir MessengerKernel._outbox).
      messengerKernel.onPeerChannelOpen(peerId);
      // Récupère l'historique de transactions de ce pair — sans ça, mon
      // solde local le concernant reste incomplet (voir WalletKernel.
      // requestSync) et je peux rejeter à tort un paiement légitime.
      walletKernel.requestSync(peerId);
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
    orderRepo = OrderRepository(db);
    tradeRepo = TradeRepository(db);
    marketKernel = MarketKernel(identity: identity, p2p: p2p, orderRepo: orderRepo, tradeRepo: tradeRepo, dag: dag);
  }

  Stream<Map<String, dynamic>> get messages => messengerKernel.messages;
  Stream<void> get walletChanges => walletKernel.walletChanges;
  DagEngine get dag => walletKernel.dag;
  WalletCore get wallet => walletKernel.wallet;

  Future<void> start({String? signalingUrl}) async {
    await walletKernel.loadPersistedLedger();
    await messengerKernel.friendRequests.load();
    Logger.info("Starting P2P node: $nodeId");

    if (signalingUrl != null) {
      _signaling = SignalingClient(signalingUrl);
      _signaling!.onConnect = () {
        isSignalingConnected = true;
        _signaling!.send({"type": "register", "id": nodeId});
        Logger.info("Registered on signaling server");
        _networkChangeController.add(null);
      };
      _signaling!.onDisconnect = () {
        isSignalingConnected = false;
        _networkChangeController.add(null);
      };
      _signaling!.onMessage = (msg) {
        health.ping(nodeId);
        _handleSignal(msg);
      };

      // Relaie les candidats ICE entre pairs via le serveur de signaling
      // — sans ça, le SDP offre/réponse est échangé mais les chemins
      // réseau ne peuvent pas être découverts, et le data channel ne
      // s'ouvre jamais (messages en file d'attente indéfiniment).
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
      case "peer_list":
        final peers = List<String>.from(msg["peers"] ?? []);
        for (final pid in peers) {
          if (pid != nodeId && !p2p.peers.containsKey(pid)) {
            // Tie-break par ID : seul le pair avec l'ID le plus grand
            // initie la connexion, l'autre attend l'offre entrante.
            // Sans ça, les deux s'envoient une offre simultanément et
            // aucun n'envoie de réponse → deadlock, messages perdus.
            if (nodeId.compareTo(pid) > 0) {
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
    if (!_admitOffer(peerId)) {
      Logger.warn("Offres WebRTC anormalement fréquentes de $peerId — ignorées");
      return;
    }
    // Connexion déjà établie (notre offre a été acceptée plus tôt) :
    // on ignore l'offre entrante.
    if (p2p.isConnectedTo(peerId)) return;

    // On avait aussi initié une connexion (tie-break ou race), on
    // abandonne notre tentative : on accepte l'offre entrante plutôt
    // que de laisser les deux envois d'offre sans réponse.
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
      peerManager.registerPeer(Peer(id: peerId, address: "", lastSeen: DateTime.now()));
      health.ping(peerId);
    } finally {
      _pendingConnections.remove(peerId);
    }
  }

  Future<void> connectToPeer(String peerId) async {
    if (peerManager.isBlocked(peerId)) return;
    if (_pendingConnections.contains(peerId)) return;
    if (p2p.isConnectedTo(peerId)) return;

    _pendingConnections.add(peerId);
    try {
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
    } finally {
      _pendingConnections.remove(peerId);
    }
  }

  Future<void> connectPeer(String addr) async {
    final peerId = addr.trim();
    if (peerId.isEmpty || peerId == nodeId) return;
    if (p2p.peers.containsKey(peerId)) return;
    if (_signaling == null || !isSignalingConnected) {
      throw StateError("Non connecté au serveur de signaling");
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

  void stop() {
    _healthTimer?.cancel();
    p2p.dispose();
    _signaling?.close();
    walletKernel.dispose();
    messengerKernel.dispose();
    _networkChangeController.close();
    _channelReadyController.close();
    marketKernel.dispose();
  }

  void reconnectSignaling() {
    if (_signaling == null) return;
    if (!isSignalingConnected) {
      Logger.info("Signaling disconnected — forcing immediate reconnection");
      _signaling!.retryNow();
    }
  }
}
