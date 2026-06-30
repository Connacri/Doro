import 'dart:convert';
import 'package:crypto/crypto.dart';

class Hash {
  static String sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}