import '../../../objectbox.g.dart';
import '../../dag/transaction_model.dart';

import '../entities/tx_entity.dart';
import '../objectbox/store.dart';

class TxRepository {
  final ObjectBoxStore _db;
  late final Box<TxEntity> _box;

  TxRepository(this._db) {
    _box = _db.getBox<TxEntity>();
  }

  List<Transaction> all() {
    return _box.getAll().map((e) => Transaction(
      id: e.txId,
      from: e.from,
      to: e.to,
      amount: BigInt.parse(e.amount),
      timestamp: e.timestamp,
      signature: "", // Reconstruct or fetch from elsewhere if needed
      nonce: 0,
      senderPublicKey: "",
      parents: [],
    )).toList();
  }

  Future<void> saveFinalized(Transaction tx) async {
    final existing = _box.query(TxEntity_.txId.equals(tx.id)).build().findFirst();
    if (existing != null) return;

    _box.put(TxEntity(
      txId: tx.id,
      from: tx.from,
      to: tx.to,
      amount: tx.amount.toString(),
      timestamp: tx.timestamp,
    ));
  }

  Future<void> load() async {
    // No-op for ObjectBox as it loads on demand or via getAll()
  }
}
