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

  bool isSignalingConnected = false;
  Timer? _healthTimer;

late final MarketKernel marketKernel;
  late final OrderRepository orderRepo;
  late final TradeRepository tradeRepo;


  P2PNode(this.identity, ObjectBoxStore db) : nodeId = identity.nodeId {
    p2p = WebRTCNetworkEngine(nodeId);
    peerManager = PeerManager(db, engine: p2p);
    health = NetworkHealth();

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
    );

    messengerKernel = MessengerKernel(
      nodeId: nodeId,
      p2p: p2p,
      db: db,
    );
orderRepo = OrderRepository(db);
    tradeRepo = TradeRepository(db);
    marketKernel = MarketKernel(identity: identity, p2p: p2p, orderRepo: orderRepo, tradeRepo: tradeRepo);

  }

  Stream<Map<String, dynamic>> get messages => messengerKernel.messages;
  Stream<void> get walletChanges => walletKernel.walletChanges;
  DagEngine get dag => walletKernel.dag;
  WalletCore get wallet => walletKernel.wallet;

  Future<void> start({String? signalingUrl}) async {
    await walletKernel.loadPersistedLedger();
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
            connectToPeer(pid);
          }
        }
        break;
    }
  }

  Future<void> _handleOffer(String peerId, dynamic sdp) async {
    if (peerManager.isBlocked(peerId)) return;
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
  }

  Future<void> connectToPeer(String peerId) async {
    if (peerManager.isBlocked(peerId)) return;
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
    final peerId = addr.trim();
    if (peerId.isEmpty || peerId == nodeId) return;
    if (p2p.peers.containsKey(peerId)) return;
    if (_signaling == null || !isSignalingConnected) {
      throw StateError("Non connecté au serveur de signaling");
    }
    await connectToPeer(peerId);
  }

  DagAcceptResult broadcastTx(Transaction tx) => walletKernel.broadcastTx(tx);
  // lib/core/p2p/p2p_node.dart — remplace UNIQUEMENT cette ligne
void sendChat(String toPeerId, String text) => messengerKernel.sendPrivateChat(toPeerId, text);
  Future<void> selfApprove(String txId) => walletKernel.selfApprove(txId);

  void stop() {
    _healthTimer?.cancel();
    p2p.dispose();
    _signaling?.close();
    walletKernel.dispose();
    messengerKernel.dispose();
    _networkChangeController.close();
marketKernel.dispose()
  }
}
