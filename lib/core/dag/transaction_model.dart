class Transaction {
  final String id;
  final String from;
  final String to;
  final BigInt amount;
  final List<String> approvals;
  final int timestamp;
  final String signature;

  Transaction({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.approvals,
    required this.timestamp,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "from": from,
    "to": to,
    "amount": amount.toString(),
    "approvals": approvals,
    "timestamp": timestamp,
    "signature": signature,
  };
}