import '../dag/transaction_model.dart';

class SyncEngine {
  final List<Transaction> buffer = [];

  void push(Transaction tx) {
    buffer.add(tx);

    // simulate persistence + broadcast sync
  }

  List<Transaction> all() => buffer;
}