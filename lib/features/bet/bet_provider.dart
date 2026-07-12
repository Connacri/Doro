// lib/features/bet/bet_provider.dart
import 'package:flutter/material.dart';
import '../../core/bet/bet_model.dart';
import '../../core/kernels/bet/bet_kernel.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/storage/secure/keypair_store.dart';

class BetProvider extends ChangeNotifier {
  final P2PNode node;
  String? lastError;

  BetProvider(this.node) {
    node.betKernel.betChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    node.betKernel.settlementChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
  }

  List<Bet> get openBets => node.betRepo.openBets();
  List<Bet> get allBets => node.betRepo.all();

  List<BetStake> stakesOf(String betId) => node.betStakeRepo.byBet(betId);
  List<BetVote> votesOf(String betId) => node.betVoteRepo.byBet(betId);

  bool hasStaked(String betId, String nodeId) =>
      stakesOf(betId).any((s) => s.stakerId == nodeId);

  BetTally tallyOf(Bet bet) => node.betKernel.computeTally(bet);

  Future<Bet?> createBet({
    required String title,
    required String description,
    required String category,
    required List<String> optionLabels,
    required DateTime stakingDeadline,
    required DateTime votingDeadline,
    required BigInt minStake,
  }) async {
    final keyPair = await KeypairStore.load(node.nodeId);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable — crée d'abord ton wallet.";
      notifyListeners();
      return null;
    }
    try {
      final bet = await node.betKernel.createAndPublishBet(
        title: title,
        description: description,
        category: category,
        optionLabels: optionLabels,
        stakingDeadline: stakingDeadline,
        votingDeadline: votingDeadline,
        minStake: minStake,
        keyPair: keyPair,
      );
      notifyListeners();
      return bet;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> stake({required Bet bet, required String optionLabel, required BigInt amount}) async {
    final keyPair = await KeypairStore.load(node.nodeId);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable.";
      notifyListeners();
      return false;
    }
    try {
      await node.betKernel.placeStake(bet: bet, optionLabel: optionLabel, amount: amount, keyPair: keyPair);
      notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> vote({required Bet bet, required String votedOptionLabel}) async {
    final keyPair = await KeypairStore.load(node.nodeId);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable.";
      notifyListeners();
      return false;
    }
    try {
      await node.betKernel.castVote(bet: bet, votedOptionLabel: votedOptionLabel, keyPair: keyPair);
      notifyListeners();
      return true;
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// À appeler quand l'utilisateur ouvre l'écran de détail d'un pari dont
  /// la fenêtre de vote est peut-être écoulée — déclenche le règlement
  /// s'il ne l'est pas déjà (idempotent, voir BetKernel.settleIfDue).
  Future<void> settleIfDue(Bet bet) => node.betKernel.settleIfDue(bet);
}
