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
      signature: e.signature,
      nonce: e.nonce,
      senderPublicKey: e.senderPublicKey,
      // "".split(',') retourne [''] et non [] — sans ce garde-fou, toute
      // transaction sans parents (ex: la genesis) est rechargée avec un
      // faux parent "" et se fait rejeter comme "parents inconnus" par
      // DagEngine au redémarrage de l'app, la faisant disparaître du DAG.
      parents: e.parents.isEmpty ? const <String>[] : e.parents.split(','),
    )).toList();
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
    ));
  }

  Future<void> load() async {
  }
}
