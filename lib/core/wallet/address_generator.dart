import 'dart:convert';
import 'package:crypto/crypto.dart';

class AddressGenerator {
  static String generate(String publicKey) {
    final hash = sha256.convert(utf8.encode(publicKey)).toString();

    return "0x${hash.substring(0, 40)}";
  }
}