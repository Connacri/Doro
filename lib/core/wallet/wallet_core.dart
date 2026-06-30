import 'wallet_model.dart';

class WalletCore {
  final Map<String, Wallet> _wallets = {};

  Wallet create(String address, String pubKey) {
    final wallet = Wallet(
      address: address,
      publicKey: pubKey,
      balance: BigInt.from(0),
    );

    _wallets[address] = wallet;
    return wallet;
  }

  Wallet? get(String address) => _wallets[address];

  bool transfer(String from, String to, BigInt amount) {
    final sender = _wallets[from];
    final receiver = _wallets[to];

    if (sender == null || receiver == null) return false;
    if (sender.balance < amount) return false;

    sender.balance -= amount;
    receiver.balance += amount;

    return true;
  }

  BigInt balanceOf(String address) {
    return _wallets[address]?.balance ?? BigInt.zero;
  }
}