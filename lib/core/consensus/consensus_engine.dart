import 'reputation_score.dart';

class ConsensusEngine {
  final ReputationScore reputation;

  ConsensusEngine(this.reputation);

  bool validate({
    required String txId,
    required List<String> validators,
  }) {
    double weight = 0;

    for (final v in validators) {
      weight += reputation.get(v);
    }

    return weight >= 50;
  }
}