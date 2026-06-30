import '../economy/staking_engine.dart';

class BFTConsensus {
  final StakingEngine staking;

  BFTConsensus(this.staking);

  bool reachFinality({
    required List<String> validators,
    required String txId,
  }) {
    double total = 0;

    for (final v in validators) {
      total += staking.weight(v);
    }

    // super-majority threshold (66%)
    return total > _threshold(validators);
  }

  double _threshold(List<String> v) {
    return v.length * 0.66;
  }
}