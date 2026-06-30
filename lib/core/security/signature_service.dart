import 'ed25519_crypto.dart';

class SignatureService {
  final Ed25519Crypto crypto = Ed25519Crypto();

  Future<bool> verifyTransaction({
    required List<int> message,
    required dynamic signature,
    required dynamic publicKey,
  }) async {
    return await crypto.verify(
      message: message,
      signature: signature,
      publicKey: publicKey,
    );
  }
}