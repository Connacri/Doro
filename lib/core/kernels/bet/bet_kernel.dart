// lib/core/kernels/bet/bet_kernel.dart
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../../crypto/signature.dart';
import '../../bet/bet_model.dart';
import '../../p2p/webrtc_engine.dart';
import '../../security/sybil_protection.dart';
import '../../storage/repositories/bet_repository.dart';
import '../../storage/repositories/bet_stake_repository.dart';
import '../../storage/repositories/bet_vote_repository.dart';
import '../../utils/id_generator.dart';
import '../../utils/node_identity.dart';
import '../../utils/logger.dart';
import '../../wallet/address_generator.dart';

/// Signature d'un envoi DORO réel, fournie par la couche wallet (typiquement
/// `WalletProvider.send` lié à `from: identity.nodeId`). Injectée plutôt
/// qu'importée directement : BetKernel ne doit pas dépendre de la couche UI,
/// exactement comme WalletKernel reste indépendant de WalletProvider.
typedef WalletSendFn = Future<String?> Function({required String to, required BigInt amount});

/// Résultat du dépouillement, recalculé indépendamment par CHAQUE pair à
/// partir des mêmes stakes/votes publics — aucun nœud n'est un "oracle"
/// unique à qui faire confiance : n'importe qui peut vérifier.
class BetTally {
  final bool isRefund;
  final String? winningOptionLabel;
  final Map<String, BigInt> payouts; // stakerId gagnant -> montant net dû (hors frais)
  final BigInt feeAmount;
  BetTally({required this.isRefund, required this.winningOptionLabel, required this.payouts, required this.feeAmount});
}

class BetKernel {
  final NodeIdentityKeyPair identity;
  final WebRTCNetworkEngine p2p;
  final BetRepository betRepo;
  final BetStakeRepository stakeRepo;
  final BetVoteRepository voteRepo;
  final SybilProtection sybil;

  /// Réglé après coup par `BetProvider` (voir `app.dart`), une fois
  /// `WalletProvider` construit — BetKernel vit dans `P2PNode`, créé AVANT
  /// la couche UI/Provider, donc cette dépendance ne peut pas être
  /// injectée au constructeur comme les autres. Tant qu'elle n'est pas
  /// réglée, tout perdant potentiel voit son auto-paiement journalisé en
  /// attente plutôt que planter.
  WalletSendFn? walletSend;

  /// Solde disponible localement pour `address`, en unité atomique — permet
  /// une vérification best-effort côté UI avant de miser (le vrai contrôle
  /// de fonds n'a lieu qu'au moment du transfert réel, au règlement).
  final BigInt Function(String address) balanceOf;

  final CryptoService _crypto = CryptoService();

  final Set<String> _seenBets = {};
  final Set<String> _seenStakes = {};
  final Set<String> _seenVotes = {};
  final Set<String> _settledBets = {};

  final _betChanges = StreamController<void>.broadcast();
  Stream<void> get betChanges => _betChanges.stream;
  final _settlementChanges = StreamController<String>.broadcast(); // betId réglé
  Stream<String> get settlementChanges => _settlementChanges.stream;

  BetKernel({
    required this.identity,
    required this.p2p,
    required this.betRepo,
    required this.stakeRepo,
    required this.voteRepo,
    required this.balanceOf,
    this.walletSend,
    SybilProtection? sybil,
  }) : sybil = sybil ?? SybilProtection() {
    p2p.messages.listen((msg) {
      final data = msg.data;
      if (data is! Map<String, dynamic>) return;
      switch (data["type"]) {
        case "bet_publish": _handleBetPublish(data, fromPeer: msg.from); break;
        case "bet_stake": _handleBetStake(data, fromPeer: msg.from); break;
        case "bet_vote": _handleBetVote(data, fromPeer: msg.from); break;
        case "bet_settled": _handleBetSettled(data, fromPeer: msg.from); break;
        case "bet_payout_proof": _handlePayoutProof(data); break;
      }
    });
  }

  // ---------------------------------------------------------------------
  // 1. CRÉATION
  // ---------------------------------------------------------------------
  Future<Bet> createAndPublishBet({
    required String title,
    required String description,
    required String category,
    required List<String> optionLabels,
    required DateTime stakingDeadline,
    required DateTime votingDeadline,
    required BigInt minStake,
    required KeyPair keyPair,
    int feeBasisPoints = 200,
    int quorumBasisPoints = 5000,
    int majorityBasisPoints = 6600,
  }) async {
    if (optionLabels.toSet().length < 2) {
      throw ArgumentError("Un pari nécessite au moins 2 options distinctes.");
    }
    if (optionLabels.any((o) => o.contains('|'))) {
      throw ArgumentError("Le caractère '|' n'est pas autorisé dans un libellé d'option.");
    }
    if (!votingDeadline.isAfter(stakingDeadline)) {
      throw ArgumentError("La fenêtre de vote doit suivre la fin des mises.");
    }

    final unsigned = Bet(
      id: IdGenerator.generateId("bet"),
      creatorId: identity.nodeId,
      creatorPublicKey: identity.publicKeyHex,
      title: title,
      description: description,
      category: category,
      optionLabels: optionLabels,
      minStake: minStake,
      feeBasisPoints: feeBasisPoints,
      stakingDeadline: stakingDeadline.millisecondsSinceEpoch,
      votingDeadline: votingDeadline.millisecondsSinceEpoch,
      quorumBasisPoints: quorumBasisPoints,
      majorityBasisPoints: majorityBasisPoints,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      signature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.hash), keyPair: keyPair);
    final bet = Bet(
      id: unsigned.id, creatorId: unsigned.creatorId, creatorPublicKey: unsigned.creatorPublicKey,
      title: unsigned.title, description: unsigned.description, category: unsigned.category,
      optionLabels: unsigned.optionLabels, minStake: unsigned.minStake, feeBasisPoints: unsigned.feeBasisPoints,
      stakingDeadline: unsigned.stakingDeadline, votingDeadline: unsigned.votingDeadline,
      quorumBasisPoints: unsigned.quorumBasisPoints, majorityBasisPoints: unsigned.majorityBasisPoints,
      timestamp: unsigned.timestamp, signature: _hex(sig.bytes),
    );

    _seenBets.add(bet.id);
    betRepo.save(bet);
    p2p.broadcast({"type": "bet_publish", ...bet.toJson()});
    _betChanges.add(null);
    return bet;
  }

  Future<void> _handleBetPublish(Map<String, dynamic> data, {String? fromPeer}) async {
    late final Bet bet;
    try {
      bet = Bet.fromJson(data);
    } catch (e) {
      Logger.warn("Pari malformé ignoré : $e");
      return;
    }
    if (_seenBets.contains(bet.id) || betRepo.exists(bet.id)) return;
    if (AddressGenerator.generate(bet.creatorPublicKey) != bet.creatorId) {
      Logger.warn("Pari ${bet.id} rejeté : creatorId incohérent avec la clé publique");
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }
    if (!await _verify(bet.hash, bet.creatorPublicKey, bet.signature)) {
      Logger.warn("Pari ${bet.id} rejeté : signature invalide");
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }
    if (bet.optionLabels.toSet().length < 2) return;
    if (bet.votingDeadline <= bet.stakingDeadline) return;

    _seenBets.add(bet.id);
    betRepo.save(bet);
    p2p.broadcast(data);
    _betChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // 2. MISE — annonce signée, PAS un transfert. Le solde du staker n'est
  // débité qu'au règlement final (voir _autoPayIfLoser). Voir
  // README section "Pourquoi pas d'escrow custodial" pour la justification.
  // ---------------------------------------------------------------------
  Future<BetStake> placeStake({
    required Bet bet,
    required String optionLabel,
    required BigInt amount,
    required KeyPair keyPair,
  }) async {
    if (!bet.optionLabels.contains(optionLabel)) {
      throw ArgumentError("Option inconnue pour ce pari.");
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > bet.stakingDeadline) {
      throw StateError("La date limite de mise est dépassée.");
    }
    if (amount < bet.minStake) {
      throw ArgumentError("Mise minimale : ${bet.minStake} (unité atomique DORO).");
    }
    if (balanceOf(identity.nodeId) < amount) {
      throw StateError("Solde DORO insuffisant.");
    }
    final already = stakeRepo.byBet(bet.id).any((s) => s.stakerId == identity.nodeId);
    if (already) {
      throw StateError("Une seule mise autorisée par participant sur ce pari.");
    }

    final unsigned = BetStake(
      id: IdGenerator.generateId("betstake"),
      betId: bet.id,
      optionLabel: optionLabel,
      stakerId: identity.nodeId,
      stakerPublicKey: identity.publicKeyHex,
      amount: amount,
      timestamp: now,
      signature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.hash), keyPair: keyPair);
    final stake = BetStake(
      id: unsigned.id, betId: unsigned.betId, optionLabel: unsigned.optionLabel,
      stakerId: unsigned.stakerId, stakerPublicKey: unsigned.stakerPublicKey,
      amount: unsigned.amount, timestamp: unsigned.timestamp, signature: _hex(sig.bytes),
    );

    _seenStakes.add(stake.id);
    stakeRepo.save(stake);
    p2p.broadcast({"type": "bet_stake", ...stake.toJson()});
    _betChanges.add(null);
    return stake;
  }

  Future<void> _handleBetStake(Map<String, dynamic> data, {String? fromPeer}) async {
    late final BetStake stake;
    try {
      stake = BetStake.fromJson(data);
    } catch (e) {
      return;
    }
    if (_seenStakes.contains(stake.id) || stakeRepo.exists(stake.id)) return;
    if (AddressGenerator.generate(stake.stakerPublicKey) != stake.stakerId) {
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }
    if (!await _verify(stake.hash, stake.stakerPublicKey, stake.signature)) {
      Logger.warn("Mise ${stake.id} rejetée : signature invalide");
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }
    final bet = betRepo.entity(stake.betId);
    if (bet == null || stake.timestamp > bet.stakingDeadline) return;
    if (!bet.optionLabelsCsv.split('|').contains(stake.optionLabel)) return;

    _seenStakes.add(stake.id);
    stakeRepo.save(stake);
    p2p.broadcast(data);
    _betChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // 3. VOTE — 1 nodeId staker = 1 voix
  // ---------------------------------------------------------------------
  Future<BetVote> castVote({
    required Bet bet,
    required String votedOptionLabel,
    required KeyPair keyPair,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= bet.stakingDeadline) throw StateError("Le vote n'est pas encore ouvert.");
    if (now > bet.votingDeadline) throw StateError("La fenêtre de vote est fermée.");
    if (!bet.optionLabels.contains(votedOptionLabel)) throw ArgumentError("Option inconnue.");

    final stakes = stakeRepo.byBet(bet.id);
    final hasStaked = stakes.any((s) => s.stakerId == identity.nodeId);
    if (!hasStaked) throw StateError("Seuls les participants ayant misé peuvent voter.");
    if (voteRepo.hasVoted(bet.id, identity.nodeId)) throw StateError("Vote déjà enregistré.");

    final unsigned = BetVote(
      id: IdGenerator.generateId("betvote"),
      betId: bet.id,
      voterId: identity.nodeId,
      voterPublicKey: identity.publicKeyHex,
      votedOptionLabel: votedOptionLabel,
      timestamp: now,
      signature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.hash), keyPair: keyPair);
    final vote = BetVote(
      id: unsigned.id, betId: unsigned.betId, voterId: unsigned.voterId,
      voterPublicKey: unsigned.voterPublicKey, votedOptionLabel: unsigned.votedOptionLabel,
      timestamp: unsigned.timestamp, signature: _hex(sig.bytes),
    );

    _seenVotes.add(vote.id);
    voteRepo.save(vote);
    p2p.broadcast({"type": "bet_vote", ...vote.toJson()});
    _betChanges.add(null);
    return vote;
  }

  Future<void> _handleBetVote(Map<String, dynamic> data, {String? fromPeer}) async {
    late final BetVote vote;
    try {
      vote = BetVote.fromJson(data);
    } catch (e) {
      return;
    }
    if (_seenVotes.contains(vote.id) || voteRepo.exists(vote.id)) return;
    if (AddressGenerator.generate(vote.voterPublicKey) != vote.voterId) {
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }
    if (!await _verify(vote.hash, vote.voterPublicKey, vote.signature)) {
      Logger.warn("Vote ${vote.id} rejeté : signature invalide");
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }
    if (voteRepo.hasVoted(vote.betId, vote.voterId)) return; // déjà un vote de ce nodeId
    final stakes = stakeRepo.byBet(vote.betId);
    if (!stakes.any((s) => s.stakerId == vote.voterId)) {
      Logger.warn("Vote ${vote.id} rejeté : ${vote.voterId} n'a pas misé sur ce pari");
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }

    _seenVotes.add(vote.id);
    voteRepo.save(vote);
    p2p.broadcast(data);
    _betChanges.add(null);
  }

  // ---------------------------------------------------------------------
  // 4. DÉPOUILLEMENT DÉTERMINISTE — n'importe quel pair peut le calculer,
  // et n'importe quel pair qui REÇOIT un "bet_settled" le recalcule pour
  // vérifier avant d'accepter : aucun nœud n'est un oracle privilégié.
  // ---------------------------------------------------------------------
  BetTally computeTally(Bet bet) {
    final stakes = stakeRepo.byBet(bet.id);
    final votes = voteRepo.byBet(bet.id);
    final distinctStakers = stakes.map((s) => s.stakerId).toSet();

    final quorumMet = distinctStakers.isEmpty
        ? false
        : (votes.length * 10000) ~/ distinctStakers.length >= bet.quorumBasisPoints;

    final tally = <String, int>{};
    for (final v in votes) {
      tally[v.votedOptionLabel] = (tally[v.votedOptionLabel] ?? 0) + 1;
    }
    String? winner;
    if (tally.isNotEmpty && votes.isNotEmpty) {
      final sorted = tally.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted.first;
      final majorityMet = (top.value * 10000) ~/ votes.length >= bet.majorityBasisPoints;
      if (majorityMet) winner = top.key;
    }

    final isRefund = !quorumMet || winner == null;
    if (isRefund) {
      return BetTally(isRefund: true, winningOptionLabel: null, payouts: {}, feeAmount: BigInt.zero);
    }

    final winningStakes = stakes.where((s) => s.optionLabel == winner).toList();
    final totalWinningStake = winningStakes.fold<BigInt>(BigInt.zero, (a, s) => a + s.amount);
    final totalPool = stakes.fold<BigInt>(BigInt.zero, (a, s) => a + s.amount);
    final feeAmount = (totalPool * BigInt.from(bet.feeBasisPoints)) ~/ BigInt.from(10000);
    final netPool = totalPool - feeAmount;

    final payouts = <String, BigInt>{};
    if (totalWinningStake > BigInt.zero) {
      for (final s in winningStakes) {
        payouts[s.stakerId] = (netPool * s.amount) ~/ totalWinningStake;
      }
    }
    return BetTally(isRefund: false, winningOptionLabel: winner, payouts: payouts, feeAmount: feeAmount);
  }

  /// À appeler par n'importe quel client (le premier à passer par ici après
  /// `votingDeadline` gagne la course, sans conséquence si plusieurs le
  /// font : tous calculent le MÊME résultat déterministe). Diffuse le
  /// résultat, puis chaque pair (y compris celui-ci) vérifie et exécute
  /// son propre paiement s'il est perdant.
  Future<void> settleIfDue(Bet bet) async {
    if (_settledBets.contains(bet.id)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now <= bet.votingDeadline) return;

    final tally = computeTally(bet);
    _settledBets.add(bet.id);
    betRepo.updateStatus(bet.id, tally.isRefund ? "refunded" : "settled",
        winningOptionLabel: tally.winningOptionLabel);

    final payload = {
      "type": "bet_settled",
      "betId": bet.id,
      "isRefund": tally.isRefund,
      "winningOptionLabel": tally.winningOptionLabel,
      "payouts": tally.payouts.map((k, v) => MapEntry(k, v.toString())),
      "computedBy": identity.nodeId,
    };
    p2p.broadcast(payload);
    _settlementChanges.add(bet.id);

    if (!tally.isRefund) {
      await _autoPayIfLoser(bet, tally);
    }
  }

  Future<void> _handleBetSettled(Map<String, dynamic> data, {String? fromPeer}) async {
    final betId = data["betId"] as String?;
    if (betId == null || _settledBets.contains(betId)) return;
    final bet = betRepo.entity(betId);
    if (bet == null) return;

    final betModel = Bet(
      id: bet.betId, creatorId: bet.creatorId, creatorPublicKey: bet.creatorPublicKey,
      title: bet.title, description: bet.description, category: bet.category,
      optionLabels: bet.optionLabelsCsv.split('|'), minStake: BigInt.parse(bet.minStake),
      feeBasisPoints: bet.feeBasisPoints, stakingDeadline: bet.stakingDeadline,
      votingDeadline: bet.votingDeadline, quorumBasisPoints: bet.quorumBasisPoints,
      majorityBasisPoints: bet.majorityBasisPoints, timestamp: bet.timestamp, signature: bet.signature,
    );
    if (DateTime.now().millisecondsSinceEpoch <= betModel.votingDeadline) return;

    // Recalcul INDÉPENDANT — le "computedBy" annoncé n'est jamais fait
    // confiance aveuglément.
    final myTally = computeTally(betModel);
    final announcedIsRefund = data["isRefund"] as bool? ?? false;
    final announcedWinner = data["winningOptionLabel"] as String?;
    if (myTally.isRefund != announcedIsRefund || myTally.winningOptionLabel != announcedWinner) {
      Logger.warn("bet_settled pour $betId rejeté : tally annoncé ne correspond pas au recalcul local");
      final computedBy = data["computedBy"] as String?;
      if (computedBy != null) sybil.decreaseTrust(computedBy);
      if (fromPeer != null) sybil.decreaseTrust(fromPeer);
      return;
    }

    _settledBets.add(betId);
    betRepo.updateStatus(betId, myTally.isRefund ? "refunded" : "settled",
        winningOptionLabel: myTally.winningOptionLabel);
    p2p.broadcast(data);
    _settlementChanges.add(betId);

    if (!myTally.isRefund) {
      await _autoPayIfLoser(betModel, myTally);
    }
  }

  /// Si JE suis un staker perdant sur ce pari, exécute automatiquement mes
  /// paiements réels (de vrais `Transaction.send` DORO, signés par MA
  /// clé), proportionnellement à la mise de chaque gagnant — pattern
  /// identique à l'auto-claim déjà existant côté WalletKernel pour les
  /// `receive`. Ni le créateur du pari ni aucun autre pair ne peut
  /// déclencher ce paiement à ma place.
  Future<void> _autoPayIfLoser(Bet bet, BetTally tally) async {
    final myStake = stakeRepo.byBet(bet.id).firstWhere(
          (s) => s.stakerId == identity.nodeId,
          orElse: () => BetStake(id: '', betId: '', optionLabel: '', stakerId: '', stakerPublicKey: '', amount: BigInt.zero, timestamp: 0, signature: ''),
        );
    if (myStake.id.isEmpty) return; // je n'ai pas misé sur ce pari
    if (myStake.optionLabel == tally.winningOptionLabel) return; // je suis gagnant, rien à payer

    // Ma part du pool perdant est répartie au prorata de la mise de chaque
    // gagnant par rapport au total misé sur l'option gagnante.
    final winningStakesTotal = _winningStakeTotal(bet, tally);
    if (winningStakesTotal == BigInt.zero) return;

    final txIds = <String>[];
    for (final entry in tally.payouts.entries) {
      final winnerId = entry.key;
      // Poids du gagnant `winnerId` dans le pool gagnant, appliqué à MA mise.
      final winnerStake = _stakeAmountOf(bet, winnerId, tally.winningOptionLabel!);
      final amountToWinner = (myStake.amount * winnerStake) ~/ winningStakesTotal;
      if (amountToWinner <= BigInt.zero) continue;
      final send = walletSend;
      if (send == null) {
        Logger.warn("Paiement de $amountToWinner à $winnerId différé : wallet pas encore câblé (BetProvider non initialisé).");
        continue;
      }
      final txId = await send(to: winnerId, amount: amountToWinner);
      if (txId != null) txIds.add(txId);
    }

    if (txIds.isNotEmpty) {
      final sig = await _crypto.signString("${bet.id}:${identity.nodeId}:${txIds.join(',')}", keyPair: identity.keyPair);
      p2p.broadcast({
        "type": "bet_payout_proof",
        "betId": bet.id,
        "payerId": identity.nodeId,
        "txIds": txIds,
        "signature": _hex(sig.bytes),
      });
    }
  }

  BigInt _winningStakeTotal(Bet bet, BetTally tally) {
    final stakes = stakeRepo.byBet(bet.id).where((s) => s.optionLabel == tally.winningOptionLabel);
    return stakes.fold<BigInt>(BigInt.zero, (a, s) => a + s.amount);
  }

  BigInt _stakeAmountOf(Bet bet, String stakerId, String optionLabel) {
    final s = stakeRepo.byBet(bet.id).where((s) => s.stakerId == stakerId && s.optionLabel == optionLabel);
    return s.isEmpty ? BigInt.zero : s.first.amount;
  }

  void _handlePayoutProof(Map<String, dynamic> data) {
    final betId = data["betId"] as String?;
    final payerId = data["payerId"] as String?;
    if (betId == null || payerId == null) return;
    final txIds = List<String>.from(data["txIds"] ?? const []);
    for (final txId in txIds) {
      final stake = stakeRepo.entitiesByBet(betId).where((s) => s.stakerId == payerId);
      if (stake.isNotEmpty) {
        stakeRepo.markPaid(stake.first.stakeId, amount: BigInt.zero, txId: txId);
      }
    }
    _betChanges.add(null);
  }

  /// Marque comme défaillant tout perdant n'ayant produit aucune preuve de
  /// paiement `graceMinutes` après le règlement — pénalité de réputation
  /// réseau, PAS un blocage cryptographique (impossible sans custody, voir
  /// README). À appeler périodiquement (ex: job toutes les 10 minutes).
  void checkDefaults(Bet bet, BetTally tally, {int graceMinutes = 60}) {
    if (tally.isRefund) return;
    final graceMs = graceMinutes * 60 * 1000;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < bet.votingDeadline + graceMs) return;

    for (final e in stakeRepo.entitiesByBet(bet.id)) {
      if (e.optionLabel == tally.winningOptionLabel) continue; // gagnant, rien à devoir
      if (e.payoutTxId != null) continue; // déjà payé
      if (e.defaulted) continue; // déjà signalé
      stakeRepo.markDefaulted(e.stakeId);
      sybil.decreaseTrust(e.stakerId);
      Logger.warn("Staker ${e.stakerId} marqué défaillant sur le pari ${bet.id} (aucun paiement après ${graceMinutes}min)");
    }
  }

  Future<bool> _verify(String message, String publicKeyHex, String signatureHex) async {
    try {
      final publicKey = SimplePublicKey(_hexToBytes(publicKeyHex), type: KeyPairType.ed25519);
      final signature = Signature(_hexToBytes(signatureHex), publicKey: publicKey);
      return await _crypto.verify(utf8.encode(message), signature: signature);
    } catch (e) {
      return false;
    }
  }

  String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  void dispose() {
    _betChanges.close();
    _settlementChanges.close();
  }
}
