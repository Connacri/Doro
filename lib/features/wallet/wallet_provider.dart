import 'package:flutter/foundation.dart';
import '../../core/storage/repositories/wallet_repository.dart';
import '../../core/storage/entities/wallet_entity.dart';

class WalletProvider extends ChangeNotifier {
  final WalletRepository repo;

  WalletProvider(this.repo);

  List<WalletEntity> _wallets = [];

  List<WalletEntity> get wallets => _wallets;

  void load() {
    _wallets = repo.all();
    notifyListeners();
  }

  void addWallet(WalletEntity wallet) {
    repo.save(wallet);
    load();
  }

  WalletEntity? getByAddress(String address) {
    return _wallets.where((w) => w.address == address).firstOrNull;
  }
}