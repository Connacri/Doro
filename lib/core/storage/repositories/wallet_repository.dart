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

  Future<void> syncFromCore(WalletCore core) async {
    final allWallets = core.all();
    for (final wallet in allWallets) {
      // Find existing
      final query = box.query(WalletEntity_.address.equals(wallet.address)).build();
      final existing = query.findFirst();
      query.close();

      if (existing != null) {
        existing.balance = wallet.balance.toString();
        box.put(existing);
      } else {
        box.put(WalletEntity(
          address: wallet.address,
          publicKey: wallet.publicKey,
          balance: wallet.balance.toString(),
        ));
      }
    }
  }
}