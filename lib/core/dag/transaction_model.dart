import 'dart:convert';
import 'package:crypto/crypto.dart';

class Transaction {
  final String id;
  final String from;
  final String to;
  final BigInt amount;
  final List<String> parents; // Standard for DAG
  final int timestamp;
  final String signature;
  final String publicKey;

  Transaction({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.parents,
    required this.timestamp,
    required this.signature,
    required this.publicKey,
  });

  static String calculateHash({
    required String from,
    required String to,
    required BigInt amount,
    required List<String> parents,
    required int timestamp,
    required String publicKey,
  }) {
    final data = "$from$to$amount${parents.join()}$timestamp$publicKey";
    return sha256.convert(utf8.encode(data)).toString();
  }

  Map<String, dynamic> toJson() => {
    "id": id,
    "from": from,
    "to": to,
    "amount": amount.toString(),
    "parents": parents,
    "timestamp": timestamp,
    "signature": signature,
    "publicKey": publicKey,
  };

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      from: json['from'],
      to: json['to'],
      amount: BigInt.parse(json['amount']),
      parents: List<String>.from(json['parents']),
      timestamp: json['timestamp'],
      signature: json['signature'],
      publicKey: json['publicKey'],
    );
  }
}
