class AppConstants {
  AppConstants._();

  // Network
  static const int maxPeers = 50;
  static const int gossipTtl = 32;
  static const Duration peerTimeout = Duration(seconds: 30);

  // DAG / Ledger
  static const int maxTxPerBlockEquivalent = 1000;
  static const int confirmationThreshold = 3;

  // Token (50B supply)
  static final BigInt maxSupply =
      BigInt.from(50_000_000_000) * BigInt.from(10).pow(18);

  // Security
  static const int reputationTrustThreshold = 20;
  static const int sybilRiskThreshold = 70;

  // Crypto
  static const String curve = "ed25519";
}