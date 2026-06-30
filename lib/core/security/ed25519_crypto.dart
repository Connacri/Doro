import 'package:cryptography/cryptography.dart';

class Ed25519Crypto {
  final Ed25519 _algo = Ed25519();

  Future<KeyPair> generateKeyPair() async {
    return await _algo.newKeyPair();
  }

  Future<Signature> sign(
      List<int> data,
      KeyPair keyPair,
      ) async {
    return await _algo.sign(
      data,
      keyPair: keyPair,
    );
  }

  Future<bool> verify({
    required List<int> message,
    required Signature signature,
    required SimplePublicKey publicKey,
  }) async {
    return await _algo.verify(
      message,
      signature: signature,
      publicKey: publicKey,
    );
  }
}