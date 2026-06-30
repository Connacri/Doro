import 'transaction_model.dart';

class DagEngine {
  final Map<String, Transaction> ledger = {};

  Function(Transaction tx)? onCommit;

  bool addFromNetwork(Map<String, dynamic> data) {
    final tx = Transaction(
      id: data["id"],
      from: data["from"],
      to: data["to"],
      amount: BigInt.parse(data["amount"]),
      approvals: List<String>.from(data["approvals"]),
      timestamp: data["timestamp"],
      signature: data["signature"],
    );

    ledger[tx.id] = tx;

    onCommit?.call(tx);

    return true;
  }

  List<Transaction> all() => ledger.values.toList();
}