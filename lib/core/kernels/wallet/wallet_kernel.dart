import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../../crypto/signature.dart';
import '../../dag/dag_engine.dart';
import '../../dag/tx_validator.dart';
import '../../dag/transaction_model.dart';
import '../../consensus/consensus_engine.dart';
import '../../wallet/wallet_core.dart';
import '../../storage/repositories/tx_repository.dart';
import '../../storage/secure/keypair_store.dart';
import '../../utils/id_generator.dart';
import '../../utils/node_identity.dart';
import '../../p2p/webrtc_engine.dart';
import '../../utils/logger.dart';

class WalletKernel {
  final NodeIdentityKeyPair identity;
  final DagEngine dag;
  final ConsensusEngine consensus;
  final WalletCore wallet;
  final TxRepository txRepo;
  final WebRTCNetworkEngine p2p;
  final CryptoService crypto = CryptoService();
  final TxValidator _txValidator = TxValidator();

  final _walletChangeController = StreamController<void>.broadcast();
  Stream<void> get walletChanges => _walletChangeController.stream;

  final Set<String> _seenApprovals = {};

  WalletKernel({
    required this.identity,
    required this.dag,
    required this.consensus,
    required this.wallet,
    required this.txRepo,
    required this.p2p,
  }) {
    _setupHandlers();
  }

  void _setupHandlers() {
    p2p.messages.listen((msg) {
      final data = msg.data;
      if (data is Map<String, dynamic>) {
        switch (data["type"]) {
          case "tx":
            _handleIncomingTx(data);
            break;
          case "tx_approve":
            _handleIncomingApprove(data);
            break;
          case "sync_request":
            _handleSyncRequest(data);
            break;
          case "sync_response":
            _handleSyncResponse(data);
            break;
        }
      }
    });

    dag.onFinalized = (tx) {
      _creditIfFinalizedHere(tx);
    };

    dag.onCommit = (tx) {
      notifyChange();
      // Un `send` qui m'est destiné (compte que je possède localement) :
      // je réclame automatiquement les fonds avec un `receive` — sans ça,
      // l'utilisateur devrait manuellement "accepter" chaque paiement
      // reçu, alors que l'ancien modèle créditait déjà tout seul.
      if (tx.type == TxType.send && wallet.get(tx.to) != null && !dag.isSendClaimed(tx.id)) {
        _autoClaim(tx);
      }
    };

    // Un `receive` qui attendait son `send` (arrivé en retard, ex: via
    // un chemin de gossip plus long) vient d'être accepté — personne
    // d'autre ne le persisterait/rediffuserait, `_handleIncomingTx` a
    // déjà rendu la main depuis longtemps quand ça arrive.
    dag.onPendingReceiveResolved = (tx) {
      p2p.broadcast({"type": "tx", ...tx.toJson()});
      txRepo.save(tx);
    };
  }

  Future<void> _handleIncomingTx(Map<String, dynamic> data) async {
    late final Transaction tx;
    try {
      tx = Transaction.fromJson(data);
    } catch (e) {
      Logger.warn("Transaction malformée ignorée : $e");
      return;
    }

    if (!_txValidator.validate(tx)) {
      Logger.warn("Transaction ${tx.id} rejetée : validation structurelle échouée");
      return;
    }

    if (!await _verifySignature(tx)) {
      Logger.warn("Transaction ${tx.id} rejetée : signature invalide");
      return;
    }

    final result = dag.addValidated(tx);
    if (result == DagAcceptResult.accepted) {
      p2p.broadcast(data);
      await selfApprove(tx.id);
      await txRepo.save(tx);
    }
  }

  /// Construit, signe et diffuse le `receive` qui réclame `sendTx` — ce
  /// bloc appartient à la chaîne du DESTINATAIRE (`sendTx.to`), c'est
  /// donc SA clé privée (pas la mienne au sens `identity`) qu'il faut
  /// utiliser pour signer, chargée via `KeypairStore`.
  Future<void> _autoClaim(Transaction sendTx) async {
    final recipient = sendTx.to;
    final recipientWallet = wallet.get(recipient);
    if (recipientWallet == null) return;

    final keyPair = await KeypairStore.load(recipient);
    if (keyPair == null) {
      Logger.warn("Pas de clé privée locale pour $recipient — impossible de réclamer ${sendTx.id}");
      return;
    }

    final lastKnown = dag.lastNonceOf(recipient);
    final nonce = (lastKnown > recipientWallet.nonce ? lastKnown : recipientWallet.nonce) + 1;

    final unsigned = Transaction(
      id: IdGenerator.generateId("receive"),
      type: TxType.receive,
      from: recipient,
      to: recipient,
      amount: sendTx.amount,
      parents: dag.tips().take(2).toList(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: nonce,
      senderPublicKey: recipientWallet.publicKey,
      signature: "",
      linkedSendId: sendTx.id,
    );

    final sig = await crypto.sign(utf8.encode(unsigned.hash), keyPair: keyPair);
    final receiveTx = Transaction(
      id: unsigned.id,
      type: TxType.receive,
      from: unsigned.from,
      to: unsigned.to,
      amount: unsigned.amount,
      parents: unsigned.parents,
      timestamp: unsigned.timestamp,
      nonce: unsigned.nonce,
      senderPublicKey: unsigned.senderPublicKey,
      signature: _bytesToHex(sig.bytes),
      linkedSendId: unsigned.linkedSendId,
    );

    final result = dag.addValidated(receiveTx);
    if (result == DagAcceptResult.accepted) {
      recipientWallet.nonce = nonce;
      p2p.broadcast({"type": "tx", ...receiveTx.toJson()});
      await txRepo.save(receiveTx);
    } else {
      Logger.warn("Auto-claim de ${sendTx.id} rejeté localement : $result");
    }
  }

  Future<void> _handleIncomingApprove(Map<String, dynamic> data) async {
    final txId = data["txId"] as String?;
    final approver = data["approver"] as String?;
    final approverPublicKey = data["approverPublicKey"] as String?;
    final signature = data["signature"] as String?;

    if (txId == null || approver == null || approverPublicKey == null || signature == null) return;
    if (approver == identity.nodeId) return;

    final approvalKey = "$txId:$approver";
    if (_seenApprovals.contains(approvalKey)) return;
    _seenApprovals.add(approvalKey);

    if (!await _verifyApprovalSignature(txId, approver, approverPublicKey, signature)) {
      Logger.warn("Vote d'approbation rejeté : signature invalide de $approver");
      return;
    }

    final justFinalized = dag.confirm(txId, approver);
    p2p.broadcast(data);

    if (justFinalized) {
      final tx = dag.ledger[txId];
      if (tx != null) _creditIfFinalizedHere(tx);
    }
  }

  Future<void> selfApprove(String txId) async {
    final approver = identity.nodeId;
    final approverPublicKey = identity.publicKeyHex;

    final sig = await crypto.sign(
      utf8.encode("$txId:$approver"),
      keyPair: identity.keyPair,
    );
    final sigHex = _bytesToHex(sig.bytes);

    final justFinalized = dag.confirm(txId, approver);

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
      "from": identity.nodeId,
      "txs": txs,
    });
  }

  /// Demande à `peerId` de nous envoyer tout son historique de
  /// transactions connu. À appeler dès qu'une connexion s'établit avec
  /// un pair — sans ça, un nœud qui vient de rejoindre le réseau ne
  /// connaît QUE les transactions diffusées après sa connexion, et peut
  /// à tort rejeter un paiement légitime d'un pair dont il n'a pas encore
  /// vu l'historique (solde local incomplet).
  void requestSync(String peerId) {
    p2p.sendToPeer(peerId, {"type": "sync_request", "from": identity.nodeId});
  }

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

      if (!_txValidator.validate(tx)) continue;
      if (!await _verifySignature(tx)) continue;

      final result = dag.restoreFinalized(tx);
      if (result == DagAcceptResult.accepted) {
        _creditIfFinalizedHere(tx);
        await txRepo.save(tx);
      }
    }
  }

  void _creditIfFinalizedHere(Transaction tx) {
    // Avec le modèle send/receive, un `send` ne crédite plus personne
    // directement — seul un `receive` (bloc de la chaîne du compte qui
    // reçoit, donc `tx.from` ici) crédite réellement un solde.
    if (tx.type != TxType.receive) return;
    final credited = wallet.creditIfLocal(tx.from, tx.amount);
    if (credited) {
      notifyChange();
    }
  }

  DagAcceptResult broadcastTx(Transaction tx) {
    final result = dag.addValidated(tx);
    if (result == DagAcceptResult.accepted) {
      p2p.broadcast({"type": "tx", ...tx.toJson()});
      txRepo.save(tx);
    }
    return result;
  }

  /// Recharge l'historique persisté localement. Les transactions
  /// enregistrées AVANT l'introduction du modèle send/receive sont
  /// relues comme de simples `send` (voir TxRepository, pas de marqueur
  /// de type) — sous l'ancien modèle, elles créditaient directement leur
  /// destinataire. Pour ne pas perdre ces fonds déjà reçus, on synthétise
  /// automatiquement le `receive` manquant pour toute adresse que CET
  /// appareil possède localement (migration one-shot, silencieuse).
  Future<void> loadPersistedLedger() async {
    await txRepo.load();
    final toMigrate = <Transaction>[];
    for (final tx in txRepo.all()) {
      final result = dag.addValidated(tx);
      if (result == DagAcceptResult.accepted) {
        dag.finality.markFinalized(tx.id);
      }
      if (tx.type == TxType.send && wallet.get(tx.to) != null && !dag.isSendClaimed(tx.id)) {
        toMigrate.add(tx);
      }
    }
    for (final sendTx in toMigrate) {
      await _autoClaim(sendTx);
    }
  }

  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  void notifyChange() {
    _walletChangeController.add(null);
  }

  void dispose() {
    _walletChangeController.close();
  }
}
