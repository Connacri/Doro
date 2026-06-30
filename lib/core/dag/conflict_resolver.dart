import 'transaction_model.dart';

class ConflictResolver {
  Transaction resolve(List<Transaction> candidates) {
    // RULE: highest timestamp + most approvals wins
    candidates.sort((a, b) {
      final scoreA = a.timestamp + a.approvals.length * 100;
      final scoreB = b.timestamp + b.approvals.length * 100;

      return scoreB.compareTo(scoreA);
    });

    return candidates.first;
  }
}