import '../dag/transaction_model.dart';

class AdvancedReconciliation {

  List<Transaction> merge(
      List<Transaction> local,
      List<Transaction> remote,
      ) {
    final Map<String, Transaction> map = {};

    for (final tx in local) {
      map[tx.id] = tx;
    }

    for (final tx in remote) {
      if (!map.containsKey(tx.id)) {
        map[tx.id] = tx;
      } else {
        final existing = map[tx.id]!;

        // stronger rule: approvals + timestamp
        if (tx.parents.length > existing.parents.length) {
          map[tx.id] = tx;
        }
      }
    }

    return map.values.toList();
  }
}