import 'wallet_model.dart';

class WalletCore {
  final Map<String, Wallet> _wallets = {};

  Wallet create(String address, String pubKey) {
    // Aucun solde implicite : un wallet fraîchement créé démarre à zéro.
    // Le seul moyen d'obtenir un solde est le faucet de debug (explicite,
    // appelé uniquement pour MON wallet local) ou une transaction reçue
    // réellement via le réseau (voir creditIfLocal).
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

  /// Crédite `address` UNIQUEMENT si ce wallet existe déjà dans ce
  /// WalletCore local (donc UNIQUEMENT si c'est un de mes wallets).
  /// Utilisé quand une transaction arrive du réseau P2P avec `to == mon
  /// adresse` : c'est le vrai crédit à réception, jamais appliqué à un
  /// wallet distant que je ne possède pas.
  bool creditIfLocal(String address, BigInt amount) {
    final wallet = _wallets[address];
    if (wallet == null) return false;
    wallet.credit(amount);
    return true;
  }

  /// Crédit unique réservé à l'allocation génésis (voir `Genesis` et
  /// `WalletProvider.importWallet`). N'est plus JAMAIS appelé pour un
  /// wallet créé normalement via `createWallet()` — ceux-là démarrent
  /// systématiquement à zéro.
  bool debugFaucet(String address, BigInt amount) {
    final wallet = _wallets[address];
    if (wallet == null) return false;
    wallet.credit(amount);
    return true;
  }
}