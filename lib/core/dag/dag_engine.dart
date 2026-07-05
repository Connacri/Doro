import 'transaction_model.dart';
import 'finality_engine.dart';
import 'ledger_balances.dart';
import '../wallet/genesis.dart';

enum DagAcceptResult {
  accepted,
  alreadyKnown,
  rejectedTampered,
  rejectedUnknownParents,
  rejectedReplay,
  rejectedInsufficientBalance,
  rejectedDuplicateGenesis,
  rejectedUnknownSend,
  rejectedInvalidReceive,
  rejectedDuplicateReceive,
}

class DagEngine {
  final Map<String, Transaction> ledger = {};
  final Map<String, int> _lastNonce = {};
  final Map<String, Set<String>> _confirmedBy = {};
  final Map<String, Set<String>> _pendingConfirmations = {};
  final FinalityEngine finality;

  /// Solde faisant AUTORITÉ pour tout le réseau — voir LedgerBalances.
  /// C'est ce qui empêche une transaction de dépenser un montant que
  /// son émetteur ne possède pas réellement, quelle que soit la
  /// signature (valide) qui l'accompagne.
  final LedgerBalances balances = LedgerBalances();

  /// `true` dès qu'une transaction de mint (genesis) a été acceptée une
  /// fois. Empêche quiconque de rediffuser une "fausse genesis" (nouvel
  /// id, sa propre clé) pour re-créditer indéfiniment l'allocation de
  /// départ — la vérification de nonce normale est sautée pour les
  /// adresses de mint, donc ce garde-fou est nécessaire séparément.
  bool _genesisMinted = false;

  /// Ids des blocs `send` déjà réclamés par un `receive` — un `send` ne
  /// peut être crédité qu'une seule fois dans tout le réseau.
  final Set<String> _claimedSendIds = {};

  /// `receive` reçus alors que le `send` qu'ils réclament n'est pas
  /// encore connu de ce nœud (ex: sur un nœud tiers, si le gossip
  /// multi-sauts fait arriver le `receive` avant le `send` — rare avec
  /// des connexions directes, possible sur un réseau maillé plus large).
  /// Rejoués automatiquement dès que le `send` correspondant arrive (voir
  /// `addValidated`). Plafonné pour éviter qu'un pair malveillant ne
  /// fasse grossir cette file indéfiniment avec des `linkedSendId` bidon.
  final Map<String, List<Transaction>> _pendingReceives = {};
  static const int _maxPendingReceives = 500;
  int _pendingReceivesCount = 0;

  /// Appelé quand un `receive` mis en attente est enfin accepté après
  /// l'arrivée tardive de son `send` — le seul cas où `onCommit` ne
  /// suffit pas : l'appelant d'origine (`_handleIncomingTx` etc.) a déjà
  /// rendu la main depuis longtemps, donc personne d'autre ne
  /// persisterait/rediffuserait ce `receive` sans ce hook dédié.
  Function(Transaction tx)? onPendingReceiveResolved;

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

    if (Genesis.isMintAddress(tx.from)) {
      // Une seule allocation genesis, jamais deux — sinon n'importe qui
      // pourrait rediffuser un mint signé de sa propre clé pour
      // re-créditer `Genesis.genesisAddress` à l'infini.
      if (_genesisMinted) {
        return DagAcceptResult.rejectedDuplicateGenesis;
      }
    } else {
      final last = _lastNonce[tx.from];
      if (last != null && tx.nonce <= last) {
        return DagAcceptResult.rejectedReplay;
      }

      if (tx.type == TxType.send) {
        // Vérification de solde FAISANT AUTORITÉ, mais qui ne dépend QUE
        // de la propre chaîne de `tx.from` — jamais de l'historique d'un
        // AUTRE compte. C'est ce qui élimine l'ambiguïté d'ordre entre
        // comptes différents : que ce nœud ait déjà vu ou non les
        // transactions des AUTRES participants n'a aucune importance
        // pour valider ce `send`-ci.
        if (!balances.canSpend(tx.from, tx.amount)) {
          return DagAcceptResult.rejectedInsufficientBalance;
        }
      } else {
        // receive : doit réclamer un `send` réel, qui m'est destiné, pas
        // déjà réclamé, et d'un montant identique.
        final linkedId = tx.linkedSendId;
        if (linkedId == null || linkedId.isEmpty) {
          return DagAcceptResult.rejectedInvalidReceive;
        }
        final sendTx = ledger[linkedId];
        if (sendTx == null) {
          // Le `send` référencé n'est pas encore connu de ce nœud : on
          // met en attente plutôt que de perdre définitivement ce
          // `receive` — il sera rejoué automatiquement dès que le `send`
          // arrivera (voir plus bas).
          if (_pendingReceivesCount >= _maxPendingReceives) {
            return DagAcceptResult.rejectedUnknownSend;
          }
          _pendingReceives.putIfAbsent(linkedId, () => []).add(tx);
          _pendingReceivesCount++;
          return DagAcceptResult.rejectedUnknownSend;
        }
        if (sendTx.type != TxType.send || sendTx.to != tx.from) {
          return DagAcceptResult.rejectedInvalidReceive;
        }
        if (_claimedSendIds.contains(linkedId)) {
          return DagAcceptResult.rejectedDuplicateReceive;
        }
        if (sendTx.amount != tx.amount) {
          return DagAcceptResult.rejectedInvalidReceive;
        }
      }
    }

    ledger[tx.id] = tx;
    if (Genesis.isMintAddress(tx.from)) {
      _genesisMinted = true;
      balances.credit(tx.to, tx.amount);
    } else {
      _lastNonce[tx.from] = tx.nonce;
      if (tx.type == TxType.send) {
        balances.debit(tx.from, tx.amount);
      } else {
        balances.credit(tx.from, tx.amount);
        _claimedSendIds.add(tx.linkedSendId!);
      }
    }
    onCommit?.call(tx);

    if (tx.type == TxType.send) {
      // Ce `send` peut débloquer un ou plusieurs `receive` qui
      // attendaient précisément lui — on les rejoue maintenant.
      final waiting = _pendingReceives.remove(tx.id);
      if (waiting != null) {
        _pendingReceivesCount -= waiting.length;
        for (final pendingReceive in waiting) {
          final result = addValidated(pendingReceive);
          if (result == DagAcceptResult.accepted) {
            onPendingReceiveResolved?.call(pendingReceive);
          }
        }
      }
    }

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

  /// Dernier nonce accepté pour cette adresse, ou 0 si aucune tx encore.
  /// Source d'autorité pour calculer le PROCHAIN nonce à utiliser — ne
  /// jamais se fier à un compteur local (ex: `Wallet.nonce`) qui n'est
  /// pas persisté après un redémarrage de l'app, sous peine de rejouer
  /// un nonce déjà utilisé et de se faire rejeter par `rejectedReplay`.
  int lastNonceOf(String address) => _lastNonce[address] ?? 0;

  /// Ce `send` a-t-il déjà été réclamé par un `receive` (par moi ou par
  /// n'importe qui d'autre sur le réseau, tel que je le sais) ?
  bool isSendClaimed(String sendId) => _claimedSendIds.contains(sendId);

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
