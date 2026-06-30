import '../dag/transaction_model.dart';

class StateReconciliation {

  List<Transaction> merge(
      List<Transaction> local,
      List<Transaction> remote,
      ) {
    final Map<String, Transaction> merged = {};

    for (final tx in local) {
      merged[tx.id] = tx;
    }

    for (final tx in remote) {
      if (!merged.containsKey(tx.id)) {
        merged[tx.id] = tx;
      } else {
        final existing = merged[tx.id]!;

        // conflict resolution simple (timestamp priority)
        if (tx.timestamp > existing.timestamp) {
          merged[tx.id] = tx;
        }
      }
    }

    return merged.values.toList();
  }
}