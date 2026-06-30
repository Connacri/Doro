import 'ed25519_crypto.dart';
import 'package:cryptography/cryptography.dart';

class SignatureService {
  final Ed25519Crypto _crypto = Ed25519Crypto();

  Future<SimpleKeyPair> generateKeyPair() {
    return _crypto.generateKeyPair();
  }

  Future<Signature> sign(List<int> data, SimpleKeyPair keyPair) {
    return _crypto.sign(data, keyPair);
  }

  Future<bool> verify({
    required List<int> message,
    required Signature signature,
    required SimplePublicKey publicKey,
  }) {
    return _crypto.verify(
      message: message,
      signature: signature,
      publicKey: publicKey,
    );
  }
}