import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/crypto/signature.dart';
import '../../core/dag/transaction_model.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/utils/id_generator.dart';
import '../../core/wallet/address_generator.dart';
import '../../core/wallet/wallet_core.dart';
import '../../core/wallet/wallet_model.dart';
import '../../core/storage/repositories/wallet_repository.dart';

/// Fonds de test attribués à MON wallet local à la création (démo/dev).
/// Jamais attribués à un wallet distant : voir WalletCore.debugFaucet.
final BigInt kDebugFaucetAmount = BigInt.from(1000) * BigInt.from(10).pow(18);

class WalletProvider extends ChangeNotifier {
  final WalletCore core;
  final WalletRepository repo;
  final P2PNode? node;
  final CryptoService _crypto = CryptoService();
  StreamSubscription<void>? _walletSub;

  WalletProvider(this.core, this.repo, {this.node}) {
    _init();

    // Quand une tx reçue crédite réellement mon wallet (voir
    // P2PNode._wire), on resynchronise l'UI et le stockage local.
    _walletSub = node?.walletChanges.listen((_) async {
      await repo.syncFromCore(core);
      notifyListeners();
    });
  }

  Future<void> _init() async {
    await repo.load();
    _restoreFromRepo();
    notifyListeners();
  }

  void _restoreFromRepo() {
    for (final w in repo.all()) {
      core.restore(w);
    }
  }

  List<Wallet> get wallets => core.all();

  Future<Wallet> createWallet() async {
    final keyPair = await _crypto.generateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final pubKeyHex = _bytesToHex((publicKey as SimplePublicKey).bytes);
    final address = AddressGenerator.generate(pubKeyHex);

    final wallet = core.create(address, pubKeyHex);

    // Le seul wallet à recevoir un solde de départ est celui que je viens
    // de créer moi-même, ici, localement. Un pair qui reçoit son propre
    // wallet sur son propre device passe par le même chemin — chacun
    // ne voit jamais que SON solde de départ, jamais celui des autres.
    core.debugFaucet(address, kDebugFaucetAmount);

    await repo.save(wallet);
    notifyListeners();

    return wallet;
  }

  Future<void> send({
    required String from,
    required String to,
    required BigInt amount,
  }) async {
    final ok = core.transfer(from, to, amount);
    if (!ok) return;

    await repo.syncFromCore(core);

    final tx = Transaction(
      id: IdGenerator.generateId("tx"),
      from: from,
      to: to,
      amount: amount,
      approvals: const [],
      timestamp: DateTime.now().millisecondsSinceEpoch,
      signature: "",
    );

    node?.broadcastTx(tx.toJson());

    notifyListeners();
  }

  void load() {
    notifyListeners();
  }

  @override
  void dispose() {
    _walletSub?.cancel();
    super.dispose();
  }

  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}