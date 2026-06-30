import 'package:flutter/foundation.dart';
import '../../core/storage/repositories/wallet_repository.dart';
import '../../core/wallet/wallet_core.dart';

class WalletProvider extends ChangeNotifier {
  final WalletRepository repo;
  final WalletCore core;

  WalletProvider(this.repo, this.core);

  void send({
    required String from,
    required String to,
    required BigInt amount,
  }) {
    final ok = core.transfer(from, to, amount);

    if (ok) {
      repo.syncFromCore(core);
      notifyListeners();
    }
  }
}