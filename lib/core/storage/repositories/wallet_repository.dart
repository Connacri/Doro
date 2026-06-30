import '../entities/wallet_entity.dart';
import 'package:objectbox/objectbox.dart';

class WalletRepository {
  final Box<WalletEntity> box;

  WalletRepository(this.box);

  void save(WalletEntity wallet) {
    box.put(wallet);
  }

  WalletEntity? find(String address) {
    return box
        .query(WalletEntity_.address.equals(address))
        .build()
        .findFirst();
  }

  List<WalletEntity> all() => box.getAll();
}