import '../dag/dag_engine.dart';
import '../dag/transaction_model.dart';
import 'wallet_model.dart';

class WalletCore {
  final DagEngine dag;
  final Map<String, Wallet> _wallets = {};

  WalletCore(this.dag);

  void registerWallet(String address, String publicKey) {
    if (!_wallets.containsKey(address)) {
      _wallets[address] = Wallet(
        address: address,
        publicKey: publicKey,
        balance: BigInt.zero,
      );
    }
  }

  Wallet? get(String address) => _wallets[address];

  BigInt getBalance(String address) {
    BigInt balance = BigInt.zero;
    
    for (final tx in dag.all()) {
      if (tx.to == address) {
        balance += tx.amount;
      }
      if (tx.from == address) {
        balance -= tx.amount;
      }
    }
    
    return balance;
  }

  List<Wallet> all() {
    // Refresh balances before returning
    for (final w in _wallets.values) {
      w.balance = getBalance(w.address);
    }
    return _wallets.values.toList();
  }
}
