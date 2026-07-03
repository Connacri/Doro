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

/// Le registre DAG local. Trois garanties structurelles sont appliquées ICI
/// (indépendamment de la validation de signature, faite en amont par
/// P2PNode) :
///
/// 1. IMMUTABILITÉ : une transaction déjà connue ne peut jamais être
///    remplacée par un contenu différent. Si quelqu'un tente de renvoyer
///    le même `id` avec des champs modifiés, son `hash` diffère de celui
///    stocké → rejeté (`rejectedTampered`).
/// 2. CHAÎNAGE : chaque tx référence des tx parentes (`parents`, des
///    hashes). Une tx dont les parents ne sont pas encore connus
///    localement est rejetée le temps que le passé soit reçu — impossible
///    d'insérer une tx "flottante" déconnectée de l'historique.
/// 3. ANTI-REJEU : le `nonce` de l'émetteur doit strictement progresser.
///    Empêche de rejouer une ancienne tx signée (double-dépense basique,
///    façon nonce Ethereum).
///
/// La FINALITÉ (confirmation par d'autres pairs) est gérée séparément par
/// [FinalityEngine] : une tx entre dans le ledger dès qu'elle passe ces
/// trois contrôles, mais n'est considérée "validée par d'autres" qu'après
/// avoir reçu des confirmations de pairs distincts (voir `confirm`).
class DagEngine {
  final Map<String, Transaction> ledger = {};
  final Map<String, int> _lastNonce = {};
  final Map<String, Set<String>> _confirmedBy = {};
  final Map<String, Set<String>> _pendingConfirmations = {};
  final FinalityEngine finality;

  DagEngine({int requiredConfirmations = 1})
      : finality = FinalityEngine(requiredConfirmations: requiredConfirmations);

  /// Appelé quand une tx entre dans le DAG local (pas encore finale).
  Function(Transaction tx)? onCommit;

  /// Appelé quand une tx atteint le seuil de confirmations d'AUTRES pairs.
  Function(Transaction tx)? onFinalized;

  /// Tips actuels : transactions non encore référencées comme parent par
  /// une autre — c'est parmi elles qu'une nouvelle tx choisit ses parents.
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

  /// Point d'entrée sûr : à appeler uniquement après validation structurelle
  /// (`TxValidator`) et vérification de signature (voir `P2PNode`).
  DagAcceptResult addValidated(Transaction tx) {
    final existing = ledger[tx.id];
    if (existing != null) {
      return existing.hash == tx.hash
          ? DagAcceptResult.alreadyKnown
          : DagAcceptResult.rejectedTampered;
    }

    if (!_parentsKnown(tx)) return DagAcceptResult.rejectedUnknownParents;

    // La tx genesis n'a pas de nonce (from = adresse de mint)
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

  /// Enregistre le vote d'un pair distinct pour `txId` (jamais l'émetteur
  /// lui-même : voir P2PNode, un node ne reçoit jamais son propre broadcast
  /// via onMessage donc ne s'auto-confirme structurellement pas).
  /// Retourne true si cette confirmation vient tout juste de rendre la tx
  /// finale.
  bool confirm(String txId, String byPeerId) {
    final tx = ledger[txId];
    if (tx == null) {
      // La confirmation est arrivée avant la tx elle-même (réseau
      // asynchrone) : on la met en attente, elle sera appliquée dès que
      // la tx sera acceptée dans addValidated().
      _pendingConfirmations.putIfAbsent(txId, () => {}).add(byPeerId);
      return false;
    }
    return _applyConfirmation(tx, byPeerId);
  }

  bool _applyConfirmation(Transaction tx, String byPeerId) {
    final voters = _confirmedBy.putIfAbsent(tx.id, () => {});
    if (voters.contains(byPeerId)) return false; // pas de double-comptage

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

  /// Revérifie que chaque tx stockée a bien tous ses parents connus
  /// localement — détecte une incohérence/corruption du ledger local.
  bool verifyIntegrity() {
    for (final tx in ledger.values) {
      if (!_parentsKnown(tx)) return false;
    }
    return true;
  }

  // --- API conservée pour compatibilité avec du code existant non branché
  // dans le flux réseau réel (ex: NetworkCore, LedgerProvider.addTx) ---

  /// Ajout brut, SANS validation ni vérification de signature.
  /// Ne jamais utiliser pour une tx reçue du réseau.
  void add(Transaction tx) {
    ledger[tx.id] = tx;
    onCommit?.call(tx);
  }

  bool addFromNetwork(Map<String, dynamic> data) {
    final tx = Transaction.fromJson(data);
    return addValidated(tx) == DagAcceptResult.accepted;
  }

  List<Transaction> all() => ledger.values.toList();
}