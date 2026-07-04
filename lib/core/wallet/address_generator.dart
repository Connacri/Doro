// lib/core/wallet/address_generator.dart
class AddressGenerator {
  /// Adresse = clé publique brute (hex), préfixée "0x". Sert désormais
  /// aussi de nodeId réseau ET de peerId de connexion WebRTC — un seul
  /// identifiant, dérivé d'une seule paire de clés, partout.
  ///
  /// Avant : sha256(clé publique) tronqué façon Ethereum. Le hash
  /// n'apportait pas de sécurité supplémentaire ici (la clé publique
  /// est de toute façon exposée dans chaque tx et chaque signaling).
  /// La sécurité d'un wallet dépend UNIQUEMENT de la clé PRIVÉE, jamais
  /// de la publique — ça ne change pas avec ce fix.
  ///
  /// ⚠️ Migration : ce changement modifie le format d'adresse (64 hex
  /// au lieu de 40) et invalide Genesis.genesisAddress — voir
  /// tool/derive_genesis_address.dart.
  static String generate(String publicKey) => "0x$publicKey";
}