import 'stake_model.dart';

class StakingEngine {
  final Map<String, Stake> _stakes = {};

  void stake(String nodeId, BigInt amount, int lockTime) {
    _stakes[nodeId] = Stake(
      nodeId: nodeId,
      amount: amount,
      lockedUntil: lockTime,
    );
  }

  double weight(String nodeId) {
    final stake = _stakes[nodeId];
    if (stake == null) return 1;

    return stake.amount.toDouble().clamp(1, 1e9);
  }
}