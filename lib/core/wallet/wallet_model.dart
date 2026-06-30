import 'dart:math';

class Wallet {
  final String address;
  BigInt balance;
  final String publicKey;

  Wallet({
    required this.address,
    required this.publicKey,
    required this.balance,
  });

  void credit(BigInt amount) {
    balance += amount;
  }

  bool debit(BigInt amount) {
    if (balance < amount) return false;
    balance -= amount;
    return true;
  }

  Map<String, dynamic> toJson() => {
    "address": address,
    "balance": balance.toString(),
    "publicKey": publicKey,
  };
}