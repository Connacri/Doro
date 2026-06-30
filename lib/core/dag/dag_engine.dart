import 'transaction_model.dart';

class DagEngine {
  final Map<String, Transaction> _ledger = {};

  final Set<String> _spentInputs = {};

  bool add(Transaction tx) {
    if (_ledger.containsKey(tx.id)) return false;

    // 1. check double spend
    if (_spentInputs.contains(tx.from)) {
      return false;
    }

    // 2. check approvals exist
    for (final ref in tx.approvals) {
      if (!_ledger.containsKey(ref)) {
        return false;
      }
    }

    // 3. accept transaction
    _ledger[tx.id] = tx;
    _spentInputs.add(tx.from);

    return true;
  }

  Transaction? get(String id) => _ledger[id];

  List<Transaction> get all => _ledger.values.toList();
}