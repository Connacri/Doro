import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persiste et recharge la clé privée (seed) Ed25519 associée à une adresse
/// de wallet, dans le stockage sécurisé du système (Keystore Android /
/// Keychain iOS — chiffré, isolé des autres apps).
///
/// Sans ceci, un wallet ne pouvait signer des transactions que pendant la
/// session où il a été créé : la clé privée retournée par
/// `crypto.generateKeyPair()` n'était jamais stockée nulle part, donc
/// perdue au redémarrage (impossible de re-signer, donc impossible pour
/// les autres de vérifier l'authenticité des futures transactions).
class KeypairStore {
  static const _storage = FlutterSecureStorage();
  static const _prefix = 'volte_privkey_';

  static Future<void> save(String address, SimpleKeyPair keyPair) async {
    final seed = await keyPair.extractPrivateKeyBytes();
    final hex = seed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: '$_prefix$address', value: hex);
  }

  static Future<SimpleKeyPair?> load(String address) async {
    final hex = await _storage.read(key: '$_prefix$address');
    if (hex == null || hex.isEmpty) return null;

    final seed = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      seed.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Ed25519().newKeyPairFromSeed(seed);
  }
}