// lib/features/bet/bet_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/bet/bet_model.dart';
import '../../core/kernels/bet/bet_kernel.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/storage/secure/keypair_store.dart';
import '../../core/utils/logger.dart';

class BetProvider extends ChangeNotifier {
  final P2PNode node;
  String? lastError;
  List<Bet> _supabaseBets = [];
  RealtimeChannel? _betsChannel;
  StreamSubscription? _betKernelSub;
  StreamSubscription? _settleSub;

  BetProvider(this.node) {
    _betKernelSub = node.betKernel.betChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    _settleSub = node.betKernel.settlementChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    loadSupabaseBets();
    subscribeToSupabaseBets();
  }

  List<Bet> get openBets {
    final now = DateTime.now().millisecondsSinceEpoch;
    return allBets.where((b) => now < b.stakingDeadline).toList();
  }

  List<Bet> get allBets => _supabaseBets.isEmpty ? node.betRepo.all() : _supabaseBets;

  List<BetStake> stakesOf(String betId) => node.betStakeRepo.byBet(betId);
  List<BetVote> votesOf(String betId) => node.betVoteRepo.byBet(betId);

  bool hasStaked(String betId, String nodeId) =>
      stakesOf(betId).any((s) => s.stakerId == nodeId);

  BetTally tallyOf(Bet bet) => node.betKernel.computeTally(bet);

  Future<void> loadSupabaseBets() async {
    try {
      final res = await Supabase.instance.client
          .from('bets')
          .select('*')
          .order('created_at', ascending: false);
      
      _supabaseBets = (res as List).map((json) {
        return Bet(
          id: json['id'] as String,
          creatorId: json['creator_id'] as String,
          creatorPublicKey: json['creator_id'] as String,
          title: json['title'] as String,
          description: json['description'] as String? ?? "",
          category: json['category'] as String? ?? "",
          optionLabels: List<String>.from(json['option_labels']),
          minStake: BigInt.parse(json['min_stake'].toString()),
          feeBasisPoints: 200,
          stakingDeadline: DateTime.parse(json['staking_deadline']).millisecondsSinceEpoch,
          votingDeadline: DateTime.parse(json['voting_deadline']).millisecondsSinceEpoch,
          timestamp: DateTime.parse(json['created_at']).millisecondsSinceEpoch,
          signature: "",
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      Logger.error("BetProvider: Error loading bets from Supabase: $e");
    }
  }

  void subscribeToSupabaseBets() {
    _betsChannel?.unsubscribe();
    _betsChannel = Supabase.instance.client
        .channel('public:bets')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bets',
          callback: (payload) {
            loadSupabaseBets();
          },
        )
        .subscribe();
  }

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
      // 1. Publish locally (P2P)
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

      // 2. Publish on Supabase
      if (bet != null) {
        await Supabase.instance.client.from('bets').insert({
          'id': bet.id,
          'creator_id': bet.creatorId,
          'title': bet.title,
          'description': bet.description,
          'category': bet.category,
          'option_labels': bet.optionLabels,
          'min_stake': bet.minStake.toString(),
          'staking_deadline': stakingDeadline.toIso8601String(),
          'voting_deadline': votingDeadline.toIso8601String(),
          'status': 'open',
        });
        await loadSupabaseBets();
      }
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

  Future<void> settleIfDue(Bet bet) => node.betKernel.settleIfDue(bet);

  @override
  void dispose() {
    _betKernelSub?.cancel();
    _settleSub?.cancel();
    _betsChannel?.unsubscribe();
    super.dispose();
  }
}
