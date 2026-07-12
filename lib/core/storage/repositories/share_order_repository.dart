// lib/core/storage/repositories/share_order_repository.dart
import '../../../objectbox.g.dart';
import '../../prediction/share_order.dart';
import '../entities/share_order_entity.dart';
import '../objectbox/store.dart';
import '../../market/order_model.dart';

class ShareOrderRepository {
  final ObjectBoxStore _db;
  Box<ShareOrderEntity>? _boxCached;
  ShareOrderRepository(this._db);
  Box<ShareOrderEntity> get _box => _boxCached ??= _db.getBox<ShareOrderEntity>();

  bool exists(String orderId) =>
      _box.query(ShareOrderEntity_.orderId.equals(orderId)).build().findFirst() != null;

  void save(ShareOrder o) {
    final existing = _box.query(ShareOrderEntity_.orderId.equals(o.id)).build().findFirst();
    if (existing != null) {
      existing.filledShares = o.filledShares.toString();
      existing.cancelled = o.cancelled;
      _box.put(existing);
      return;
    }
    _box.put(ShareOrderEntity(
      orderId: o.id, eventId: o.eventId, outcome: o.outcome,
      makerId: o.makerId, makerPublicKey: o.makerPublicKey,
      side: o.side.name, shares: o.shares.toString(),
      filledShares: o.filledShares.toString(), pricePerShare: o.pricePerShare.toString(),
      timestamp: o.timestamp, signature: o.signature, cancelled: o.cancelled,
    ));
  }

  ShareOrder? get(String orderId) {
    final e = _box.query(ShareOrderEntity_.orderId.equals(orderId)).build().findFirst();
    return e == null ? null : _toModel(e);
  }

  List<ShareOrder> all() => _box.getAll().map(_toModel).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<ShareOrder> openOrdersForEvent(String eventId) =>
      all().where((o) => o.eventId == eventId && o.isOpen).toList();

  ShareOrder _toModel(ShareOrderEntity e) => ShareOrder(
        id: e.orderId, eventId: e.eventId, outcome: e.outcome,
        makerId: e.makerId, makerPublicKey: e.makerPublicKey,
        side: e.side == "buy" ? OrderSide.buy : OrderSide.sell,
        shares: BigInt.parse(e.shares), filledShares: BigInt.parse(e.filledShares),
        pricePerShare: BigInt.parse(e.pricePerShare), timestamp: e.timestamp,
        signature: e.signature, cancelled: e.cancelled,
      );
}
