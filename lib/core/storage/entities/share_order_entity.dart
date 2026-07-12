// lib/core/storage/entities/share_order_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class ShareOrderEntity {
  int id = 0;

  @Index()
  @Unique()
  final String orderId;

  @Index()
  final String eventId;
  final String outcome; // "yes" | "no"
  
  @Index()
  final String makerId;
  final String makerPublicKey;
  final String side; // "buy" | "sell"
  final String shares; // BigInt sérialisé
  String filledShares; // BigInt sérialisé
  final String pricePerShare; // BigInt sérialisé
  final int timestamp;
  final String signature;
  bool cancelled;

  ShareOrderEntity({
    this.id = 0,
    required this.orderId,
    required this.eventId,
    required this.outcome,
    required this.makerId,
    required this.makerPublicKey,
    required this.side,
    required this.shares,
    required this.filledShares,
    required this.pricePerShare,
    required this.timestamp,
    required this.signature,
    this.cancelled = false,
  });
}
