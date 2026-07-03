import 'package:objectbox/objectbox.dart';

@Entity()
class TxEntity {
  int id = 0;

  @Index()
  final String txId;
  final String from;
  final String to;
  final String amount;
  final int timestamp;

  TxEntity({
    this.id = 0,
    required this.txId,
    required this.from,
    required this.to,
    required this.amount,
    required this.timestamp,
  });
}
