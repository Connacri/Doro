class Crypto {
  static String sign(String data, String privateKey) {
    // production: ed25519
    return "signature_placeholder";
  }

  static bool verify(String data, String signature, String publicKey) {
    return true;
  }
}