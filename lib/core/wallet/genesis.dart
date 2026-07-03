/// Allocation "génésis" — le modèle utilisé par la quasi-totalité des
/// tokens/cryptos qui ont un fondateur ou une trésorerie de lancement
/// (pré-mine) : une seule adresse, connue de tous les nodes, reçoit
/// l'intégralité de l'offre de départ. Tous les autres wallets démarrent
/// à zéro et ne reçoivent des fonds que par transaction réelle, reçue et
/// confirmée par d'autres pairs.
///
/// Ce qui rend ça sûr : `genesisAddress` est PUBLIQUE (c'est juste un hash
/// de clé publique, comme n'importe quelle adresse), mais elle ne peut
/// être "réclamée" que par celui qui possède la clé privée correspondante.
/// Un utilisateur normal qui crée un wallet obtient une adresse aléatoire
/// différente à CHAQUE fois (`WalletProvider.createWallet()`) — il ne
/// peut donc jamais, même par hasard, tomber sur cette adresse précise.
/// Seul `WalletProvider.importWallet()` avec la bonne clé privée peut
/// aboutir à `genesisAddress`.
///
/// La transaction genesis est créée et diffusée sur le réseau P2P comme
/// une vraie transaction (signée avec la clé privée fondatrice). Tous les
/// pairs l'acceptent et créditent localement le wallet fondateur.
class Genesis {
  /// Adresse du wallet fondateur/trésorerie (Ramzi). Dérivée par
  /// sha256(clé publique) — voir AddressGenerator.generate().
  static const String genesisAddress =
      "0x05ef5fa9991402ede9e8339d715469276c908b7d";

  /// Adresse "émettrice" de la transaction genesis — représente le réseau
  /// lui-même (mint). Aucune clé privée ne correspond à cette adresse,
  /// mais la transaction est signée avec la clé privée fondatrice pour
  /// prouver son authenticité.
  static const String genesisMintAddress =
      "0x0000000000000000000000000000000000000000";

  /// Offre totale allouée au wallet fondateur au moment de sa création.
  /// 50 000 000 000 DORO (18 décimales), modifiable selon les besoins.
  static final BigInt maxSupply =
      BigInt.from(50000000000) * BigInt.from(10).pow(18);

  static bool isGenesisAddress(String address) => address == genesisAddress;

  static bool isMintAddress(String address) => address == genesisMintAddress;
}