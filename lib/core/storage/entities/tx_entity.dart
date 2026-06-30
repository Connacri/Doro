import 'package:objectbox/objectbox.dart';

@Entity()
class TxEntity {
  int id = 0;

  String txId;
  String from;
  String to;
  String amount;
  int timestamp;

  TxEntity({
    required this.txId,
    required this.from,
    required this.to,
    required this.amount,
    required this.timestamp,
  });
}