// lib/core/storage/entities/trade_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class TradeEntity {
  int id = 0;

  @Index()
  @Unique()
  final String tradeId;
  final String orderId;
  final String sellerId;
  final String buyerId;
  final String amount;
  final String pricePerUnit;
  final String currency;
  final int timestamp;
  String status;
  String? txId;

  TradeEntity({
    this.id = 0,
    required this.tradeId,
    required this.orderId,
    required this.sellerId,
    required this.buyerId,
    required this.amount,
    required this.pricePerUnit,
    required this.currency,
    required this.timestamp,
    required this.status,
    this.txId,
  });
}