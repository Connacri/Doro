// tool/derive_genesis_address.dart
import 'dart:io';
import 'package:cryptography/cryptography.dart';

/// Usage : dart run tool/derive_genesis_address.dart <seedHex_64_caracteres>
/// Ne transmet jamais la seed nulle part — calcul 100% local.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln("Usage: dart run tool/derive_genesis_address.dart <seedHex>");
    exit(1);
  }
  final seed = _hexToBytes(args.first.trim());
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final pubKeyHex =
      publicKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  print("Nouvelle Genesis.genesisAddress = 0x$pubKeyHex");
}

List<int> _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}