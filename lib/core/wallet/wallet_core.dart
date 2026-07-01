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

  /// Réinjecte un wallet déjà existant (ex: rechargé depuis le repository)
  /// sans réinitialiser son solde à zéro.
  void restore(Wallet wallet) {
    _wallets[wallet.address] = wallet;
  }

  Wallet? get(String address) => _wallets[address];

  List<Wallet> all() => _wallets.values.toList();

  bool transfer(String from, String to, BigInt amount) {
    final sender = _wallets[from];
    final receiver = _wallets[to];

    if (sender == null || receiver == null) return false;
    if (sender.balance < amount) return false;

    sender.debit(amount);
    receiver.credit(amount);

    return true;
  }

  BigInt balanceOf(String address) {
    return _wallets[address]?.balance ?? BigInt.zero;
  }
}