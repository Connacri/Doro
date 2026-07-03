import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../crypto/signature.dart';
import '../gossip/gossip_engine.dart';
import '../dag/dag_engine.dart';
import '../dag/tx_validator.dart';
import '../dag/transaction_model.dart';
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

  final TxValidator _txValidator = TxValidator();

  /// Dédoublonnage des relais d'approbation ("tx_approve"), par
  /// `"txId:approverId"`, pour éviter une boucle de rediffusion infinie
  /// dans un mesh où plusieurs pairs sont connectés entre eux.
  final Set<String> _seenApprovals = {};

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  final StreamController<void> _networkChangeController =
      StreamController<void>.broadcast();

  Stream<void> get networkChanges => _networkChangeController.stream;

  final StreamController<void> _walletChangeController =
      StreamController<void>.broadcast();

  /// Émet un événement chaque fois que MON wallet local est crédité —
  /// ce qui n'arrive désormais QU'après qu'une transaction a été validée
  /// (signature correcte) ET confirmée par au moins un pair distinct de
  /// l'émetteur (voir `DagEngine.finality`).
  Stream<void> get walletChanges => _walletChangeController.stream;

  SignalingClient? _signaling;
  Timer? _healthTimer;

  bool isSignalingConnected = false;

  P2PNode(this.nodeId, {int requiredConfirmations = 1}) {
    crypto = CryptoService();
    p2p = WebRTCNetworkEngine();
    gossip = GossipEngine();
    dag = DagEngine(requiredConfirmations: requiredConfirmations);
    sync = SyncEngine();
    consensus = ConsensusEngine(ReputationScore());
    wallet = WalletCore();
    health = NetworkHealth();
    peerManager = PeerManager(engine: p2p);

    _wire();
  }

  void _wire() {
    p2p.onMessage = (from, msg) {
      _handleIncoming(from, msg);
    };

    dag.onCommit = (tx) {
      sync.push(tx);
    };

    p2p.onPeerConnected = (peerId) {
      health.ping(peerId);
      if (!_networkChangeController.isClosed) _networkChangeController.add(null);
    };

    p2p.onPeerDisconnected = (peerId) {
      if (!_networkChangeController.isClosed) _networkChangeController.add(null);
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

  Future<void> _handleIncoming(String from, String msg) async {
    try {
      final data = jsonDecode(msg);
      _messageController.add({"from": from, "data": data});

      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      switch (map["type"]) {
        case "tx":
          await _handleIncomingTx(map);
          break;
        case "tx_approve":
          _handleIncomingApprove(map);
          break;
      }
    } catch (e) {
      Logger.error("Failed to process message from $from: $e");
    }
  }

  /// Chemin complet de réception d'une transaction :
  ///  1. validation structurelle (montant, adresses, adresse ⇔ clé publique)
  ///  2. vérification cryptographique de la signature Ed25519
  ///  3. insertion dans le DAG (immuabilité + chaînage + anti-rejeu)
  ///  4. si acceptée : je diffuse MON vote de validation aux autres pairs,
  ///     et je relaie la tx elle-même pour aider sa propagation.
  /// Le crédit du solde du destinataire n'intervient QUE plus tard, quand
  /// la tx atteint la finalité (voir _handleIncomingApprove).
  Future<void> _handleIncomingTx(Map<String, dynamic> data) async {
    late final Transaction tx;
    try {
      tx = Transaction.fromJson(data);
    } catch (e) {
      Logger.warn("Tx malformée ignorée : $e");
      return;
    }

    if (!_txValidator.validate(tx)) {
      Logger.warn("Tx ${tx.id} rejetée : validation structurelle échouée");
      return;
    }

    if (!await _verifySignature(tx)) {
      Logger.warn("Tx ${tx.id} rejetée : signature invalide");
      return;
    }

    final result = dag.addValidated(tx);
    switch (result) {
      case DagAcceptResult.accepted:
        // Je viens de valider cette tx moi-même : je le fais savoir aux
        // autres pairs (c'est ÇA, "validée par d'autres" — chaque pair qui
        // la reçoit et la valide vote pour elle).
        p2p.broadcast({"type": "tx_approve", "txId": tx.id, "approver": nodeId});
        // Je relaie aussi la tx d'origine, pour qu'elle atteigne des pairs
        // qui ne sont pas directement connectés à son émetteur.
        p2p.broadcast({"type": "tx", ...tx.toJson()});

        // Si des confirmations étaient déjà arrivées avant la tx elle-même
        // (réseau asynchrone), il est possible qu'elle soit déjà finale.
        if (dag.isFinal(tx.id)) {
          _creditIfFinalizedHere(tx);
        }
        break;
      case DagAcceptResult.rejectedTampered:
        Logger.error(
          "Tx ${tx.id} REJETÉE : contenu falsifié — le hash ne correspond "
          "pas à la version déjà connue de cette transaction.",
        );
        break;
      case DagAcceptResult.rejectedUnknownParents:
        Logger.warn("Tx ${tx.id} en attente : parents inconnus localement");
        break;
      case DagAcceptResult.rejectedReplay:
        Logger.error("Tx ${tx.id} REJETÉE : nonce déjà utilisé (tentative de rejeu)");
        break;
      case DagAcceptResult.alreadyKnown:
        break;
    }
  }

  void _handleIncomingApprove(Map<String, dynamic> data) {
    final txId = data["txId"] as String?;
    final approver = data["approver"] as String?;
    if (txId == null || approver == null) return;
    if (approver == nodeId) return;

    final key = "$txId:$approver";
    if (_seenApprovals.contains(key)) return;
    _seenApprovals.add(key);

    final justFinalized = dag.confirm(txId, approver);

    // Relai borné : chaque (tx, approbateur) n'est rediffusé qu'une fois
    // par node, ce qui propage l'info sans boucle infinie dans un mesh.
    p2p.broadcast({"type": "tx_approve", "txId": txId, "approver": approver});

    if (justFinalized) {
      final tx = dag.ledger[txId];
      if (tx != null) _creditIfFinalizedHere(tx);
    }
  }

  void _creditIfFinalizedHere(Transaction tx) {
    final credited = wallet.creditIfLocal(tx.to, tx.amount);
    if (credited && !_walletChangeController.isClosed) {
      _walletChangeController.add(null);
    }
  }

  /// Vérifie que `tx.signature` est bien une signature Ed25519 valide de
  /// `tx.hash` par la clé publique `tx.senderPublicKey`. C'est ce qui
  /// garantit qu'une transaction n'a pu être créée que par le détenteur
  /// de la clé privée de l'adresse émettrice — personne d'autre ne peut
  /// forger une tx en usurpant `from`.
  Future<bool> _verifySignature(Transaction tx) async {
    try {
      final publicKey = SimplePublicKey(
        _hexToBytes(tx.senderPublicKey),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(
        _hexToBytes(tx.signature),
        publicKey: publicKey,
      );
      return await crypto.verify(utf8.encode(tx.hash), signature: signature);
    } catch (e) {
      Logger.warn("Signature illisible pour tx ${tx.id} : $e");
      return false;
    }
  }

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  Future<void> start({String? signalingUrl}) async {
    Logger.info("Starting P2P node: $nodeId");

    if (signalingUrl != null) {
      _signaling = SignalingClient(signalingUrl);
      _signaling!.onConnect = () {
        isSignalingConnected = true;
        _signaling!.send({"type": "register", "id": nodeId});
        Logger.info("Registered on signaling server");
        if (!_networkChangeController.isClosed) _networkChangeController.add(null);
      };
      _signaling!.onDisconnect = () {
        isSignalingConnected = false;
        if (!_networkChangeController.isClosed) _networkChangeController.add(null);
      };
      _signaling!.onMessage = (msg) {
        health.ping(nodeId);
        _handleSignal(msg);
      };
    }

    health.ping(nodeId);
    if (!_networkChangeController.isClosed) _networkChangeController.add(null);

    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      health.ping(nodeId);
      if (!_networkChangeController.isClosed) _networkChangeController.add(null);
    });
  }

  void _handleSignal(Map<String, dynamic> msg) {
    final type = msg["type"] as String?;
    if (type == null) return;

    switch (type) {
      case "offer":
        final peerId = msg["from"] as String;
        final sdp = msg["sdp"];
        _handleOffer(peerId, sdp);
        break;
      case "answer":
        final peerId = msg["from"] as String;
        final sdp = msg["sdp"];
        _handleAnswer(peerId, sdp);
        break;
      case "ice":
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

  /// Connexion à un pair à partir de son ID (collé manuellement ou lu via
  /// QR code). C'est le point d'entrée utilisé par l'UI "Ajouter un pair".
  Future<void> connectPeer(String addr) async {
    final peerId = addr.trim();
    if (peerId.isEmpty || peerId == nodeId) return;
    if (p2p.peers.containsKey(peerId)) return;
    if (_signaling == null || !isSignalingConnected) {
      throw StateError(
        "Non connecté au serveur de signaling — impossible d'ajouter un pair pour l'instant.",
      );
    }
    await connectToPeer(peerId);
  }

  /// Diffuse une transaction déjà signée par MOI. L'appelant (WalletProvider)
  /// garantit l'authenticité en signant avec la clé privée du wallet
  /// émetteur avant d'appeler cette méthode. L'insertion locale passe quand
  /// même par `addValidated` pour garder les mêmes garanties d'intégrité
  /// (immuabilité, chaînage, anti-rejeu) que pour une tx reçue du réseau.
  DagAcceptResult broadcastTx(Transaction tx) {
    final result = dag.addValidated(tx);
    if (result == DagAcceptResult.accepted) {
      p2p.broadcast({"type": "tx", ...tx.toJson()});
    }
    return result;
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
    _healthTimer?.cancel();
    await p2p.dispose();
    _signaling?.close();
    await _messageController.close();
    await _networkChangeController.close();
    await _walletChangeController.close();
    Logger.info("P2P node $nodeId stopped");
  }
}