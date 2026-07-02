class Wallet {
  final String address;
  BigInt balance;
  final String publicKey;

  /// Compteur strictement croissant, incrémenté à chaque envoi. Inclus
  /// dans chaque transaction signée pour empêcher qu'une ancienne tx
  /// signée soit rejouée (double-dépense par rejeu).
  int nonce;

  Wallet({
    required this.address,
    required this.publicKey,
    required this.balance,
    this.nonce = 0,
  });

  void credit(BigInt amount) {
    balance += amount;
  }

  bool debit(BigInt amount) {
    if (balance < amount) return false;
    balance -= amount;
    return true;
  }

  /// À appeler une seule fois par transaction envoyée, juste avant de la
  /// signer, pour obtenir le nonce à utiliser.
  int nextNonce() {
    nonce += 1;
    return nonce;
  }

  Map<String, dynamic> toJson() => {
    "address": address,
    "balance": balance.toString(),
    "publicKey": publicKey,
    "nonce": nonce,
  };
}