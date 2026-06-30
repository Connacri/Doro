import 'package:cryptography/cryptography.dart';

class SignatureService {
  final ed25519 = Ed25519();

  Future<SimpleKeyPair> generate() {
    return ed25519.newKeyPair();
  }

  Future<Signature> sign(List<int> data, SimpleKeyPair keyPair) {
    return ed25519.sign(data, keyPair: keyPair);
  }

  Future<bool> verify({
    required List<int> message,
    required Signature signature,
    required SimplePublicKey publicKey,
  }) {
    return ed25519.verify(
      message,
      signature: signature,
      publicKey: publicKey,
    );
  }
}