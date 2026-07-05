import 'wallet_model.dart';
import '../utils/logger.dart';

class WalletCore {
  final Map<String, Wallet> _wallets = {};

  Wallet create(String address, String pubKey) {
    final wallet = Wallet(
      address: address,
      publicKey: pubKey,
      balance: BigInt.zero,
    );

    _wallets[address] = wallet;
    return wallet;
  }

  void restore(Wallet wallet) {
    _wallets[wallet.address] = wallet;
  }

  Wallet? get(String address) => _wallets[address];

  List<Wallet> all() => _wallets.values.toList();

  bool transfer(String from, String to, BigInt amount) {
    final sender = _wallets[from];
    if (sender == null) return false;
    if (sender.balance < amount) return false;

    sender.debit(amount);

    final receiver = _wallets[to];
    if (receiver != null) {
      receiver.credit(amount);
    }

    return true;
  }

  BigInt balanceOf(String address) {
    return _wallets[address]?.balance ?? BigInt.zero;
  }

  bool creditIfLocal(String address, BigInt amount) {
    final wallet = _wallets[address];
    if (wallet == null) return false;
    wallet.credit(amount);
    Logger.info("Local wallet $address credited with $amount");
    return true;
  }

  void clear() {
    _wallets.clear();
  }

  bool debugFaucet(String address, BigInt amount) {
    final wallet = _wallets[address];
    if (wallet == null) return false;
    wallet.credit(amount);
    return true;
  }
}
