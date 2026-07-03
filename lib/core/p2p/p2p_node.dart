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
import '../storage/objectbox/store.dart';
import '../storage/repositories/tx_repository.dart';
import '../utils/logger.dart';
import '../utils/node_identity.dart';
import '../wallet/address_generator.dart';
import 'peer_model.dart';
import 'webrtc_engine.dart';
import 'signaling_client.dart';
import 'peer_manager.dart';

class P2PNode {
  final String nodeId;

  /// Identité cryptographique du node (clé Ed25519 dont `nodeId` est
  /// dérivé). Sert à SIGNER chaque vote de confirmation (`tx_approve`)
  /// qu'on émet — voir `_broadcastApproval` / `selfApprove` — pour qu'un
  /// pair receveur puisse vérifier que le vote vient bien du détenteur
  /// réel de ce nodeId, et pas d'un texte libre inventé par un tiers.
  final NodeIdentityKeyPair identity;

  late final CryptoService crypto;
  late final WebRTCNetworkEngine p2p;
  late final GossipEngine gossip;
  late final DagEngine dag;
  late final SyncEngine sync;
  late final ConsensusEngine consensus;
  late final WalletCore wallet;
  late final NetworkHealth health;
  late final PeerManager peerManager;
  late final TxRepository txRepo;

  final TxValidator _txValidator = TxValidator();

  /// Dédoublonnage des relais d'approbation ("tx_approve"), par
  /// `"txId:approverId"`, pour éviter une boucle de rediffusion infinie
  /// dans un mesh où plusieurs pairs sont connectés entre eux.
  final Set<String> _seenApprovals = {};

  /// Dédoublonnage des messages de chat pour éviter les boucles infinies
  /// lors du relai (gossip).
  final Set<String> _seenChatMessages = {};

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

  P2PNode(this.identity, ObjectBoxStore db, {int requiredConfirmations = 1}) : nodeId = identity.nodeId {
    crypto = CryptoService();
    p2p = WebRTCNetworkEngine();
    gossip = GossipEngine();
    dag = DagEngine(requiredConfirmations: requiredConfirmations);
    sync = SyncEngine();
    consensus = ConsensusEngine(ReputationScore());
    wallet = WalletCore();
    health = NetworkHealth();
    peerManager = PeerManager(engine: p2p);
    txRepo = TxRepository(db);

    _wire();
  }

  void _wire() {
    p2p.onMessage = (from, msg) {
      _handleIncoming(from, msg);
    };

    dag.onCommit = (tx) {
      sync.push(tx);
    };

    dag.onFinalized = (tx) {
      txRepo.saveFinalized(tx);
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

    p2p.onChannelOpen = (peerId) {
      _sendSyncRequest(peerId);
    };
  }

  /// Envoyé sur le DATA CHANNEL P2P (pas le WebSocket de signaling : ce
  /// dernier ne relaie que offer/answer/ice/peer_list, et n'a aucun `case`
  /// pour "sync_request" — l'envoyer par ce canal le fait disparaître
  /// silencieusement côté pair receveur, sans erreur ni log).
  void _sendSyncRequest(String peerId) {
    p2p.sendToPeer(peerId, {
      "type": "sync_request",
      "from": nodeId,
    });
  }

  Future<void> _handleIncoming(String from, String msg) async {
    try {
      final data = jsonDecode(msg);

      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      switch (map["type"]) {
        case "tx":
          await _handleIncomingTx(map);
          break;
        case "tx_approve":
          await _handleIncomingApprove(map);
          break;
        case "chat":
          _handleIncomingChat(from, map);
          break;
        case "sync_request":
          _handleSyncRequest(map);
          break;
        case "sync_response":
          await _handleSyncResponse(map);
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
      // la reçoit et la valide vote pour elle). Le vote est SIGNÉ par
      // mon identité — voir _broadcastApproval.
        await _broadcastApproval(tx.id);
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

  /// Diffuse MON propre vote de confirmation pour `txId`, signé par mon
  /// identité de node. Utilisé aussi bien pour une tx que je viens de
  /// valider en direct (`_handleIncomingTx`) que pour une tx que
  /// j'insère et confirme moi-même côté émetteur (voir
  /// `selfApprove`, utilisé pour la tx genesis dans `WalletProvider`).
  Future<void> _broadcastApproval(String txId) async {
    final payload = utf8.encode("$txId:$nodeId");
    final signature = await crypto.sign(payload, keyPair: identity.keyPair);
    p2p.broadcast({
      "type": "tx_approve",
      "txId": txId,
      "approver": nodeId,
      "approverPublicKey": identity.publicKeyHex,
      "signature": _bytesToHex(signature.bytes),
    });
  }

  /// Point d'entrée public : signe et diffuse mon vote pour une tx que
  /// j'ai déjà acceptée et confirmée localement moi-même (`dag.confirm`).
  /// Remplace l'ancien `p2p.broadcast({"type": "tx_approve", ...})`
  /// appelé directement depuis `WalletProvider` pour la tx genesis, qui
  /// envoyait un `approver` en texte libre, sans aucune signature.
  Future<void> selfApprove(String txId) => _broadcastApproval(txId);

  /// AVANT ce fix : `approver` était une chaîne libre du JSON reçu, sans
  /// AUCUNE preuve de possession de ce nodeId. N'importe quel pair
  /// connecté (un seul suffit) pouvait diffuser un `tx_approve` en
  /// prétendant être un nodeId arbitraire — y compris un nodeId jamais
  /// rencontré — et fabriquer autant de "votes distincts" qu'il voulait
  /// pour atteindre artificiellement le seuil de finalité, sans avoir
  /// besoin de plusieurs appareils ni d'aucune vraie connexion P2P
  /// supplémentaire.
  ///
  /// APRÈS ce fix, un vote n'est compté QUE si les trois conditions
  /// suivantes sont TOUTES vraies :
  ///  1. le `nodeId` annoncé est bien le hash de la clé publique fournie
  ///     (on ne peut pas coller un nodeId choisi à une vraie clé) ;
  ///  2. la signature Ed25519 de "txId:approver" est valide pour cette
  ///     clé publique (donc émise par le détenteur réel de la clé
  ///     privée correspondante — personne d'autre ne peut la forger) ;
  ///  3. ce nodeId n'est pas bloqué par la protection anti-Sybil locale.
  ///
  /// Limite assumée, à documenter clairement pour l'équipe : ceci
  /// élimine l'usurpation gratuite d'un nodeId qu'on ne possède pas, mais
  /// n'empêche pas un attaquant déterminé de générer plusieurs identités
  /// RÉELLES et distinctes (une paire de clés Ed25519 se génère en
  /// quelques millisecondes, sans coût). Sans mécanisme économique
  /// (stake avec slashing, ou preuve de travail) pour rendre chaque
  /// identité coûteuse à produire, un Sybil-resistance TOTALE n'existe
  /// dans aucun système P2P connu — Bitcoin lui-même ne résout pas ce
  /// problème par l'authentification, mais par le coût du calcul (PoW).
  /// Ce fix ferme le trou de forgerie gratuite ; `staking_engine.dart`
  /// (présent dans le repo mais non branché) est la pièce qui manque
  /// pour aller plus loin.
  Future<void> _handleIncomingApprove(Map<String, dynamic> data) async {
    final txId = data["txId"] as String?;
    final approver = data["approver"] as String?;
    final approverPublicKey = data["approverPublicKey"] as String?;
    final sigHex = data["signature"] as String?;
    if (txId == null || approver == null || approverPublicKey == null || sigHex == null) {
      return;
    }
    if (approver == nodeId) return;

    if (AddressGenerator.generate(approverPublicKey) != approver) {
      Logger.warn(
        "tx_approve rejeté : le nodeId annoncé ($approver) ne correspond "
            "pas à la clé publique fournie — usurpation d'identité probable.",
      );
      return;
    }

    if (!await _verifyApprovalSignature(txId, approver, approverPublicKey, sigHex)) {
      Logger.warn("tx_approve rejeté : signature invalide pour $approver");
      return;
    }

    if (peerManager.isBlocked(approver)) {
      Logger.warn("tx_approve ignoré : $approver est bloqué par la protection anti-Sybil");
      return;
    }

    final key = "$txId:$approver";
    if (_seenApprovals.contains(key)) return;
    _seenApprovals.add(key);

    final justFinalized = dag.confirm(txId, approver);

    // Relai borné : chaque (tx, approbateur) n'est rediffusé qu'une fois
    // par node, ce qui propage l'info sans boucle infinie dans un mesh.
    // On relaie la signature d'origine telle quelle — on ne re-signe
    // jamais un vote qui n'est pas le nôtre.
    p2p.broadcast({
      "type": "tx_approve",
      "txId": txId,
      "approver": approver,
      "approverPublicKey": approverPublicKey,
      "signature": sigHex,
    });

    if (justFinalized) {
      final tx = dag.ledger[txId];
      if (tx != null) _creditIfFinalizedHere(tx);
    }
  }

  Future<bool> _verifyApprovalSignature(
      String txId,
      String approver,
      String approverPublicKeyHex,
      String sigHex,
      ) async {
    try {
      final publicKey = SimplePublicKey(
        _hexToBytes(approverPublicKeyHex),
        type: KeyPairType.ed25519,
      );
      final signature = Signature(_hexToBytes(sigHex), publicKey: publicKey);
      return await crypto.verify(
        utf8.encode("$txId:$approver"),
        signature: signature,
      );
    } catch (e) {
      Logger.warn("Signature de vote illisible pour $approver : $e");
      return false;
    }
  }

  void _handleSyncRequest(Map<String, dynamic> data) {
    final from = data["from"] as String?;
    if (from == null) return;
    final txs = dag.all().map((tx) => tx.toJson()).toList();
    p2p.sendToPeer(from, {
      "type": "sync_response",
      "to": from,
      "from": nodeId,
      "txs": txs,
    });
  }

  /// Rattrapage reçu d'UN pair : chaque tx repasse par les mêmes contrôles
  /// qu'une tx reçue en direct (structure + signature Ed25519) — le fait
  /// qu'un pair l'annonce comme "finale" ne dispense jamais de vérifier
  /// l'authenticité, sinon un seul pair malveillant pourrait injecter un
  /// faux historique dans un nouvel appareil qui n'a encore aucune
  /// référence locale pour le contredire.
  ///
  /// `restoreFinalized()` appelle `finality.markFinalized()` directement
  /// SANS déclencher `onFinalized` (qui ne sert qu'au chemin de
  /// confirmation "live"). Sans le crédit explicite ci-dessous, un
  /// appareil qui rattrape son historique via sync verrait son DAG
  /// complet mais son solde de wallet resterait à zéro pour tout ce
  /// qu'il a "reçu" avant sa reconnexion.
  Future<void> _handleSyncResponse(Map<String, dynamic> data) async {
    final txs = data["txs"] as List?;
    if (txs == null) return;

    for (final item in txs) {
      late final Transaction tx;
      try {
        tx = Transaction.fromJson(Map<String, dynamic>.from(item));
      } catch (e) {
        Logger.warn("Tx de sync malformée ignorée : $e");
        continue;
      }

      if (!_txValidator.validate(tx)) {
        Logger.warn("Tx de sync ${tx.id} rejetée : validation structurelle échouée");
        continue;
      }

      if (!await _verifySignature(tx)) {
        Logger.warn("Tx de sync ${tx.id} rejetée : signature invalide");
        continue;
      }

      final result = dag.restoreFinalized(tx);
      if (result == DagAcceptResult.accepted) {
        _creditIfFinalizedHere(tx);
      }
    }
  }

  void _handleIncomingChat(String from, Map<String, dynamic> data) {
    final fromId = data["from"] as String?;
    final text = data["text"] as String?;
    final time = data["time"] as String?;

    if (fromId == null || text == null || time == null) return;
    if (fromId == nodeId) return;

    // Utilisation d'une clé composite pour le dédoublonnage
    final msgKey = "$fromId:$time:${text.hashCode}";
    if (_seenChatMessages.contains(msgKey)) return;
    _seenChatMessages.add(msgKey);

    // Émettre pour l'UI locale
    _messageController.add({"from": from, "data": data});

    // Relayer aux autres pairs
    p2p.broadcast(data);
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

  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Future<void> start({String? signalingUrl}) async {
    await _loadPersistedLedger();
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

  Future<void> _handleAnswer(String peerId, dynamic sdp) async {
    await p2p.handleAnswer(peerId, sdp);
    health.ping(peerId);
  }

  Future<void> _handleIce(String peerId, dynamic candidate) async {
    await p2p.handleIce(peerId, candidate);
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
    final time = DateTime.now().toIso8601String();
    final data = {
      "type": "chat",
      "from": nodeId,
      "text": text,
      "time": time,
    };

    // Marquer comme vu pour ne pas le traiter s'il nous revient par relai
    final msgKey = "$nodeId:$time:${text.hashCode}";
    _seenChatMessages.add(msgKey);

    p2p.broadcast(data);
  }

  Future<void> _loadPersistedLedger() async {
    await txRepo.load();
    for (final tx in txRepo.all()) {
      dag.restoreFinalized(tx);
    }
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