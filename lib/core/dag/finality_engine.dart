import 'transaction_model.dart';

class FinalityEngine {
  final Map<String, int> confirmations = {};

  void addConfirmation(String txId) {
    confirmations[txId] = (confirmations[txId] ?? 0) + 1;
  }

  bool isFinal(String txId) {
    return (confirmations[txId] ?? 0) >= 3;
  }

  void prune(List<Transaction> ledger) {
    ledger.removeWhere((tx) => !isFinal(tx.id));
  }
}