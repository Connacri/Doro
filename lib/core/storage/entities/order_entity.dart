// lib/core/storage/entities/order_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class OrderEntity {
  int id = 0;

  @Index()
  @Unique()
  final String orderId;
  final String makerId;
  final String makerPublicKey;
  final String side;
  final String amount;
  final String pricePerUnit;
  final String currency;
  final int timestamp;
  final String signature;
  bool cancelled;
  bool filled;

  OrderEntity({
    this.id = 0,
    required this.orderId,
    required this.makerId,
    required this.makerPublicKey,
    required this.side,
    required this.amount,
    required this.pricePerUnit,
    required this.currency,
    required this.timestamp,
    required this.signature,
    this.cancelled = false,
    this.filled = false,
  });
}