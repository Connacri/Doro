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
    return _box.getAll().map((e) {
      final parents = e.parents.isEmpty ? const <String>[] : e.parents.split(',');
      return Transaction(
        id: e.txId,
        type: e.type == 'receive' ? TxType.receive : TxType.send,
        from: e.from,
        to: e.to,
        amount: BigInt.parse(e.amount),
        timestamp: e.timestamp,
        signature: e.signature,
        nonce: e.nonce,
        senderPublicKey: e.senderPublicKey,
        parents: parents,
        linkedSendId: e.linkedSendId,
      );
    }).toList();
  }

  Future<void> save(Transaction tx) async {
    final existing = _box.query(TxEntity_.txId.equals(tx.id)).build().findFirst();
    if (existing != null) return;

    _box.put(TxEntity(
      txId: tx.id,
      from: tx.from,
      to: tx.to,
      amount: tx.amount.toString(),
      timestamp: tx.timestamp,
      signature: tx.signature,
      nonce: tx.nonce,
      senderPublicKey: tx.senderPublicKey,
      parents: tx.parents.join(','),
      type: tx.type.name,
      linkedSendId: tx.type == TxType.receive ? tx.linkedSendId : null,
    ));
  }

  Future<void> load() async {
  }
}
