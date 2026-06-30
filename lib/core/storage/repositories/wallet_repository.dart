import '../entities/wallet_entity.dart';
import '../../wallet/wallet_core.dart';
import 'package:objectbox/objectbox.dart';

class WalletRepository {
  final Box<WalletEntity> box;

  WalletRepository(this.box);

  void save(WalletEntity w) {
    box.put(w);
  }

  List<WalletEntity> all() => box.getAll();

  void syncFromCore(WalletCore core) {
    for (final wallet in core.all()) {
      box.put(WalletEntity(
        address: wallet.address,
        publicKey: wallet.publicKey,
        balance: wallet.balance.toString(),
      ));
    }
  }
}