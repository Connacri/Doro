import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/crypto/signature.dart';
import '../../core/dag/dag_engine.dart';
import '../../core/dag/transaction_model.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/storage/secure/keypair_store.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/logger.dart';
import '../../core/wallet/address_generator.dart';
import '../../core/wallet/genesis.dart';
import '../../core/wallet/wallet_core.dart';
import '../../core/wallet/wallet_model.dart';
import '../../core/storage/repositories/wallet_repository.dart';

class WalletProvider extends ChangeNotifier {
  final WalletCore core;
  final WalletRepository repo;
  final P2PNode? node;
  final CryptoService _crypto = CryptoService();
  StreamSubscription<void>? _walletSub;

  WalletProvider(this.core, this.repo, {this.node}) {
    _init();

    // Quand une tx reçue crédite réellement mon wallet (validée +
    // confirmée par d'autres pairs), on resynchronise l'UI et le stockage.
    _walletSub = node?.walletChanges.listen((_) async {
      await repo.syncFromCore(core);
      notifyListeners();
    });
  }

  Future<void> _init() async {
    await repo.load();
    _restoreFromRepo();

    if (core.all().isEmpty) {
      final result = await createWallet();
      pendingBackupSeed = result.seedHex;
    }

    notifyListeners();
  }

  void clearPendingBackup() {
    pendingBackupSeed = null;
    notifyListeners();
  }





  void _restoreFromRepo() {
    for (final w in repo.all()) {
      core.restore(w);
    }
  }

  List<Wallet> get wallets => core.all();

  /// Crée un NOUVEAU wallet avec une adresse aléatoire fraîche.
  /// Démarre TOUJOURS à solde zéro — aucune exception, aucun faucet
  /// implicite. C'est le comportement pour n'importe quel utilisateur.
  /// Crée un wallet et retourne le wallet + la seed hex à montrer à
  /// l'utilisateur pour sauvegarde (seed = sa clé privée, NECESSAIRE
  /// pour récupérer l'accès si l'appareil est perdu ou réinitialisé).
  Future<({Wallet wallet, String seedHex})> createWallet() async {
    final keyPair = (await _crypto.generateKeyPair()) as SimpleKeyPair;
    final publicKey = await keyPair.extractPublicKey();
    final pubKeyHex = _bytesToHex(publicKey.bytes);
    final address = AddressGenerator.generate(pubKeyHex);

    final seedHex = _bytesToHex(await keyPair.extractPrivateKeyBytes());
    await KeypairStore.save(address, keyPair);

    final wallet = core.create(address, pubKeyHex);
    await repo.save(wallet);
    notifyListeners();

    return (wallet: wallet, seedHex: seedHex);
  }

  /// Restaure un wallet à partir d'une clé privée existante (seed Ed25519,
  /// 64 caractères hex). Sert à deux choses :
  ///  1. Récupérer un wallet existant sur un nouvel appareil.
  ///  2. Réclamer le wallet fondateur/trésorerie : si la clé fournie
  ///     dérive vers `Genesis.genesisAddress`, l'allocation totale est
  ///     créditée UNE SEULE FOIS (idempotent — un second import sur le
  ///     même wallet ne re-crédite pas si le solde n'est déjà plus zéro).
  ///     Personne d'autre ne peut obtenir ce crédit : il faut posséder la
  ///     clé privée exacte, jamais partagée nulle part dans le code.
  Future<Wallet> importWallet(String privateKeySeedHex) async {
    final seed = _hexToBytes(privateKeySeedHex.trim());
    if (seed.length != 32) {
      throw ArgumentError("La clé privée doit faire 32 octets (64 caractères hex)");
    }

    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final pubKeyHex = _bytesToHex(publicKey.bytes);
    final address = AddressGenerator.generate(pubKeyHex);

    await KeypairStore.save(address, keyPair);

    var wallet = core.get(address);
    wallet ??= core.create(address, pubKeyHex);

    if (Genesis.isGenesisAddress(address) && wallet.balance == BigInt.zero) {
      if (node != null) {
        final unsigned = Transaction(
          id: IdGenerator.generateId("genesis"),
          from: Genesis.genesisMintAddress,
          to: address,
          amount: Genesis.maxSupply,
          parents: const [],
          timestamp: DateTime.now().millisecondsSinceEpoch,
          nonce: 0,
          senderPublicKey: pubKeyHex,
          signature: "",
        );

        final signature = await _crypto.sign(
          utf8.encode(unsigned.hash),
          keyPair: keyPair,
        );

        final genesisTx = Transaction(
          id: unsigned.id,
          from: unsigned.from,
          to: unsigned.to,
          amount: unsigned.amount,
          parents: unsigned.parents,
          timestamp: unsigned.timestamp,
          nonce: unsigned.nonce,
          senderPublicKey: unsigned.senderPublicKey,
          signature: _bytesToHex(signature.bytes),
        );

        final result = node!.dag.addValidated(genesisTx);
        if (result == DagAcceptResult.accepted) {
          node!.p2p.broadcast({"type": "tx", ...genesisTx.toJson()});
          node!.dag.confirm(genesisTx.id, node!.nodeId);
          core.creditIfLocal(address, Genesis.maxSupply);
          // Vote signé par l'identité du node — jamais un "approver" en
          // texte libre non prouvé (voir P2PNode.selfApprove).
          await node!.selfApprove(genesisTx.id);
          Logger.info("Transaction genesis diffusée sur le réseau");
        } else {
          Logger.warn("Transaction genesis refusée par le DAG local : $result");
          core.debugFaucet(address, Genesis.maxSupply);
        }
      } else {
        core.debugFaucet(address, Genesis.maxSupply);
      }
      Logger.info("Wallet fondateur restauré : allocation génésis créditée");
    }

    await repo.syncFromCore(core);
    notifyListeners();
    return wallet;
  }

  Future<bool> send({
    required String from,
    required String to,
    required BigInt amount,
  }) async {
    final senderWallet = core.get(from);
    if (senderWallet == null) return false;

    final keyPair = await KeypairStore.load(from);
    if (keyPair == null) {
      Logger.error("Pas de clé privée locale pour $from — envoi impossible");
      return false;
    }

    final ok = core.transfer(from, to, amount);
    if (!ok) return false;

    final nonce = senderWallet.nextNonce();
    final parentTips = node?.dag.tips() ?? const <String>[];

    final unsigned = Transaction(
      id: IdGenerator.generateId("tx"),
      from: from,
      to: to,
      amount: amount,
      parents: parentTips.take(2).toList(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: nonce,
      senderPublicKey: senderWallet.publicKey,
      signature: "",
    );

    final signature = await _crypto.sign(
      utf8.encode(unsigned.hash),
      keyPair: keyPair,
    );

    final signedTx = Transaction(
      id: unsigned.id,
      from: unsigned.from,
      to: unsigned.to,
      amount: unsigned.amount,
      parents: unsigned.parents,
      timestamp: unsigned.timestamp,
      nonce: unsigned.nonce,
      senderPublicKey: unsigned.senderPublicKey,
      signature: _bytesToHex(signature.bytes),
    );

    final result = node?.broadcastTx(signedTx);
    if (result != null && result != DagAcceptResult.accepted) {
      Logger.error("Ma propre tx ${signedTx.id} n'a pas été acceptée localement : $result");
    }

    await repo.syncFromCore(core); // persiste le nouveau solde ET le nonce
    notifyListeners();
    return true;
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

  List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}