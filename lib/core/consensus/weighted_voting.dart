import 'reputation_score.dart';

class WeightedVoting {
  final ReputationScore reputation;

  WeightedVoting(this.reputation);

  bool approve(List<String> validators) {
    double score = 0;

    for (final v in validators) {
      score += reputation.get(v);
    }

    return score > 50;
  }
}