import 'dart:math';

class TokenConfig {
  TokenConfig._();

  static const String name = "NovaCoin";
  static const String symbol = "NVC";

  // 50 billion fixed supply (18 decimals)
  static final BigInt maxSupply =
      BigInt.from(50) * BigInt.from(10).pow(9) * BigInt.from(10).pow(18);

  static BigInt circulating = BigInt.zero;

  static const int decimals = 18;
}