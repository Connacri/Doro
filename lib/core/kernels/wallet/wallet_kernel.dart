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
    final credited = wallet.creditIfLocal(tx.to, tx.amount);
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

  Future<void> loadPersistedLedger() async {
    await txRepo.load();
    for (final tx in txRepo.all()) {
      dag.addValidated(tx);
      dag.finality.markFinalized(tx.id);
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
