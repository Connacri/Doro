import '../../../objectbox.g.dart';

import '../../wallet/wallet_core.dart';
import '../../wallet/wallet_model.dart';
import '../entities/wallet_entity.dart';
import '../objectbox/store.dart';

class WalletRepository {
  final ObjectBoxStore _db;
  Box<WalletEntity>? _boxCached;

  WalletRepository(this._db);

  Box<WalletEntity> get _box => _boxCached ??= _db.getBox<WalletEntity>();

  Future<void> save(Wallet w) async {
    final existing = _box.query(WalletEntity_.address.equals(w.address)).build().findFirst();
    if (existing != null) {
      _box.put(WalletEntity(
        id: existing.id,
        address: w.address,
        publicKey: w.publicKey,
        balance: w.balance.toString(),
      ));
    } else {
      _box.put(WalletEntity(
        address: w.address,
        publicKey: w.publicKey,
        balance: w.balance.toString(),
      ));
    }
  }

  List<Wallet> all() {
    return _box.getAll().map((e) => Wallet(
      address: e.address,
      publicKey: e.publicKey,
      balance: BigInt.parse(e.balance),
      nonce: 0, // Should be part of entity if needed
    )).toList();
  }

  Future<void> syncFromCore(WalletCore core) async {
    _box.removeAll();
    for (final w in core.all()) {
      await save(w);
    }
  }

  Future<void> removeAll() async {
    _box.removeAll();
  }

  Future<void> load() async {
    // No-op for ObjectBox
  }
}
