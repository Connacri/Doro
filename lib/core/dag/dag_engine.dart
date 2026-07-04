import 'transaction_model.dart';
import 'finality_engine.dart';
import '../wallet/genesis.dart';

enum DagAcceptResult {
  accepted,
  alreadyKnown,
  rejectedTampered,
  rejectedUnknownParents,
  rejectedReplay,
}

class DagEngine {
  final Map<String, Transaction> ledger = {};
  final Map<String, int> _lastNonce = {};
  final Map<String, Set<String>> _confirmedBy = {};
  final Map<String, Set<String>> _pendingConfirmations = {};
  final FinalityEngine finality;

  DagEngine({int requiredConfirmations = 2})
      : finality = FinalityEngine(requiredConfirmations: requiredConfirmations);

  Function(Transaction tx)? onCommit;
  Function(Transaction tx)? onFinalized;

  List<String> tips() {
    final referenced = <String>{};
    for (final tx in ledger.values) {
      referenced.addAll(tx.parents);
    }
    final tips = ledger.keys.where((id) => !referenced.contains(id)).toList();
    return tips.isEmpty ? ledger.keys.toList() : tips;
  }

  bool _parentsKnown(Transaction tx) =>
      tx.parents.every((p) => ledger.containsKey(p));

  DagAcceptResult addValidated(Transaction tx) {
    final existing = ledger[tx.id];
    if (existing != null) {
      return existing.hash == tx.hash
          ? DagAcceptResult.alreadyKnown
          : DagAcceptResult.rejectedTampered;
    }

    if (tx.parents.isNotEmpty && !_parentsKnown(tx)) {
       return DagAcceptResult.rejectedUnknownParents;
    }

    if (!Genesis.isMintAddress(tx.from)) {
      final last = _lastNonce[tx.from];
      if (last != null && tx.nonce <= last) {
        return DagAcceptResult.rejectedReplay;
      }
    }

    ledger[tx.id] = tx;
    if (!Genesis.isMintAddress(tx.from)) {
      _lastNonce[tx.from] = tx.nonce;
    }
    onCommit?.call(tx);

    final pending = _pendingConfirmations.remove(tx.id);
    if (pending != null) {
      for (final peerId in pending) {
        _applyConfirmation(tx, peerId);
      }
    }

    return DagAcceptResult.accepted;
  }

  bool confirm(String txId, String byPeerId) {
    final tx = ledger[txId];
    if (tx == null) {
      _pendingConfirmations.putIfAbsent(txId, () => {}).add(byPeerId);
      return false;
    }
    return _applyConfirmation(tx, byPeerId);
  }

  bool _applyConfirmation(Transaction tx, String byPeerId) {
    final voters = _confirmedBy.putIfAbsent(tx.id, () => {});
    if (voters.contains(byPeerId)) return false;

    voters.add(byPeerId);
    final wasFinal = finality.isFinal(tx.id);
    finality.addConfirmation(tx.id);
    final isFinalNow = finality.isFinal(tx.id);

    if (!wasFinal && isFinalNow) {
      onFinalized?.call(tx);
      return true;
    }
    return false;
  }

  bool isFinal(String txId) => finality.isFinal(txId);
  int confirmationsOf(String txId) => finality.confirmationsOf(txId);
  int confirmersCountOf(String txId) => _confirmedBy[txId]?.length ?? 0;

  DagAcceptResult restoreFinalized(Transaction tx) {
    final result = addValidated(tx);
    if (result == DagAcceptResult.accepted) {
      finality.markFinalized(tx.id);
    }
    return result;
  }

  bool verifyIntegrity() {
    for (final tx in ledger.values) {
      if (tx.parents.isNotEmpty && !_parentsKnown(tx)) return false;
    }
    return true;
  }

  List<Transaction> all() => ledger.values.toList();
}
