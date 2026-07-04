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
  final String signature;
  final int nonce;
  final String senderPublicKey;
  final String parents;

  TxEntity({
    this.id = 0,
    required this.txId,
    required this.from,
    required this.to,
    required this.amount,
    required this.timestamp,
    this.signature = "",
    this.nonce = 0,
    this.senderPublicKey = "",
    this.parents = "",
  });
}
