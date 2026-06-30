import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class IdGenerator {
  static final Random _random = Random.secure();

  /// Génère un ID unique cryptographiquement robuste
  static String generateId(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomBytes = List<int>.generate(16, (_) => _random.nextInt(256));

    final raw = "$prefix-$timestamp-${base64UrlEncode(randomBytes)}";

    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// ID court (UI / logs)
  static String shortId(String input) {
    return sha256.convert(utf8.encode(input)).toString().substring(0, 12);
  }
}