// lib/core/storage/repositories/order_repository.dart
import '../../../objectbox.g.dart';
import '../../market/order_model.dart';
import '../entities/order_entity.dart';
import '../objectbox/store.dart';

class OrderRepository {
  final ObjectBoxStore _db;
  Box<OrderEntity>? _boxCached;
  OrderRepository(this._db);
  Box<OrderEntity> get _box => _boxCached ??= _db.getBox<OrderEntity>();

  bool exists(String orderId) => _box.query(OrderEntity_.orderId.equals(orderId)).build().findFirst() != null;

  void save(Order o) {
    if (exists(o.id)) return;
    _box.put(OrderEntity(
      orderId: o.id, makerId: o.makerId, makerPublicKey: o.makerPublicKey,
      side: o.side.name, amount: o.amount.toString(), pricePerUnit: o.pricePerUnit.toString(),
      currency: o.currency, timestamp: o.timestamp, signature: o.signature,
    ));
  }

  void markCancelled(String orderId) {
    final e = _box.query(OrderEntity_.orderId.equals(orderId)).build().findFirst();
    if (e == null) return;
    e.cancelled = true;
    _box.put(e);
  }

  void markFilled(String orderId) {
    final e = _box.query(OrderEntity_.orderId.equals(orderId)).build().findFirst();
    if (e == null) return;
    e.filled = true;
    _box.put(e);
  }

  List<Order> openSells() => _openBySide("sell")..sort((a, b) => a.pricePerUnit.compareTo(b.pricePerUnit));
  List<Order> openBuys() => _openBySide("buy")..sort((a, b) => b.pricePerUnit.compareTo(a.pricePerUnit));

  List<Order> _openBySide(String side) {
    return _box
        .query(OrderEntity_.side.equals(side) & OrderEntity_.cancelled.equals(false) & OrderEntity_.filled.equals(false))
        .build()
        .find()
        .map(_toModel)
        .toList();
  }

  Order _toModel(OrderEntity e) => Order(
        id: e.orderId, makerId: e.makerId, makerPublicKey: e.makerPublicKey,
        side: e.side == "buy" ? OrderSide.buy : OrderSide.sell,
        amount: BigInt.parse(e.amount), pricePerUnit: BigInt.parse(e.pricePerUnit),
        currency: e.currency, timestamp: e.timestamp, signature: e.signature,
      );
}