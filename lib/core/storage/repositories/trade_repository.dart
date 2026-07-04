// lib/core/storage/repositories/trade_repository.dart
import '../../../objectbox.g.dart';
import '../../market/trade_model.dart';
import '../entities/trade_entity.dart';
import '../objectbox/store.dart';

class TradeRepository {
  final ObjectBoxStore _db;
  Box<TradeEntity>? _boxCached;
  TradeRepository(this._db);
  Box<TradeEntity> get _box => _boxCached ??= _db.getBox<TradeEntity>();

  void save(Trade t) {
    final existing = _box.query(TradeEntity_.tradeId.equals(t.id)).build().findFirst();
    if (existing != null) {
      existing.status = t.status.name;
      existing.txId = t.txId;
      _box.put(existing);
      return;
    }
    _box.put(TradeEntity(
      tradeId: t.id, orderId: t.orderId, sellerId: t.sellerId, buyerId: t.buyerId,
      amount: t.amount.toString(), pricePerUnit: t.pricePerUnit.toString(),
      currency: t.currency, timestamp: t.timestamp, status: t.status.name, txId: t.txId,
    ));
  }

  /// Trades confirmés triés du plus ancien au plus récent — alimente le
  /// graphe de prix avec des prix RÉELLEMENT échangés, jamais inventés.
  List<Trade> confirmedHistory() =>
      _box.query(TradeEntity_.status.equals("confirmed")).build().find().map(_toModel).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  List<Trade> all() => _box.getAll().map(_toModel).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Trade _toModel(TradeEntity e) => Trade(
        id: e.tradeId, orderId: e.orderId, sellerId: e.sellerId, buyerId: e.buyerId,
        amount: BigInt.parse(e.amount), pricePerUnit: BigInt.parse(e.pricePerUnit),
        currency: e.currency, timestamp: e.timestamp,
        status: TradeStatus.values.firstWhere((s) => s.name == e.status, orElse: () => TradeStatus.pending),
        txId: e.txId,
      );
}