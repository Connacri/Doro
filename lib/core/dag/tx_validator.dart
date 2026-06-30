import 'transaction_model.dart';

class TxValidator {
  bool validate(Transaction tx) {
    if (tx.amount <= BigInt.zero) return false;

    if (tx.from.isEmpty || tx.to.isEmpty) return false;

    if (tx.signature.isEmpty) return false;

    if (tx.approvals.isEmpty) return false;

    return true;
  }
}