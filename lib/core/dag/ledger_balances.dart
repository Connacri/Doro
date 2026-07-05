import '../wallet/genesis.dart';

/// Solde AUTORITAIRE de chaque adresse, calculé UNIQUEMENT à partir des
/// transactions acceptées dans le DAG — jamais depuis une valeur locale
/// non vérifiée côté client (voir WalletCore, qui lui n'est qu'un cache
/// UI pour les wallets possédés par CET appareil).
///
/// Point clé : `DagEngine` appelle ce ledger pour CHAQUE transaction,
/// qu'elle vienne de moi, du réseau, ou d'une resynchronisation. Comme
/// tout pair honnête applique exactement la même règle dans le même
/// ordre d'acceptation, tous les nœuds convergent vers le même état.
/// Une transaction qui prétend dépenser plus que le solde connu de son
/// émetteur est donc rejetée par TOUT le réseau, pas seulement par
/// l'expéditeur — c'est ce qui rend la dépense falsifiée impossible,
/// même si elle est parfaitement signée.
class LedgerBalances {
  final Map<String, BigInt> _balances = {};

  BigInt balanceOf(String address) => _balances[address] ?? BigInt.zero;

  /// Vérifie qu'une dépense de `amount` par `address` est possible, SANS
  /// l'appliquer. Les adresses de mint (genesis) sont exemptées : elles
  /// ne débitent jamais un solde réel, elles créent l'allocation initiale
  /// (protégée séparément contre le rejeu — voir DagEngine).
  bool canSpend(String address, BigInt amount) {
    if (Genesis.isMintAddress(address)) return true;
    return balanceOf(address) >= amount;
  }

  /// Débite `address` de `amount` — utilisé par un bloc `send` ACCEPTÉ.
  /// Ne crédite personne : les fonds restent "en attente" jusqu'à ce
  /// qu'un `receive` correspondant les réclame (voir DagEngine).
  void debit(String address, BigInt amount) {
    if (!Genesis.isMintAddress(address)) {
      _balances[address] = balanceOf(address) - amount;
    }
  }

  /// Crédite `address` de `amount` — utilisé par un bloc `receive`
  /// ACCEPTÉ (le compte qui réclame un `send`), ou par la transaction
  /// de mint (genesis), le seul cas où un crédit n'a pas de débit
  /// correspondant ailleurs dans le ledger.
  void credit(String address, BigInt amount) {
    _balances[address] = balanceOf(address) + amount;
  }

  /// Conservé pour compatibilité : débite `from` et crédite `to` en une
  /// fois. N'est plus utilisé que pour le cas mint (from = adresse de
  /// mint, exemptée de débit par construction — voir `debit`).
  void apply(String from, String to, BigInt amount) {
    debit(from, amount);
    credit(to, amount);
  }

  /// Restaure un état de solde déjà calculé (ex: après relecture du
  /// stockage local) sans repasser par `apply`.
  void restore(Map<String, BigInt> snapshot) {
    _balances
      ..clear()
      ..addAll(snapshot);
  }

  Map<String, BigInt> snapshot() => Map.unmodifiable(_balances);

  void clear() => _balances.clear();
}
