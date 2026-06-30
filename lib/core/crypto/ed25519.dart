import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class Crypto {
  static final _algorithm = Ed25519();

  static Future<KeyPair> generateKeyPair() async {
    return await _algorithm.newKeyPair();
  }

  static Future<String> sign(String data, KeyPair keyPair) async {
    final signature = await _algorithm.sign(
      utf8.encode(data),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }

  static Future<bool> verify(String data, String signatureBase64, String publicKeyBase64) async {
    try {
      final signatureBytes = base64Decode(signatureBase64);
      final publicKeyBytes = base64Decode(publicKeyBase64);
      
      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );

      return await _algorithm.verify(
        utf8.encode(data),
        signature: signature,
      );
    } catch (e) {
      return false;
    }
  }

  static Future<String> getPublicKey(KeyPair keyPair) async {
    final pk = await keyPair.extractPublicKey();
    return base64Encode(pk.bytes);
  }
}
