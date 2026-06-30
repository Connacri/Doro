import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DeviceFingerprint {
  static Future<String> generate() async {
    final data = {
      "os": Platform.operatingSystem,
      "version": Platform.operatingSystemVersion,
      "arch": Platform.localHostname,
    };

    final raw = jsonEncode(data);

    return sha256.convert(utf8.encode(raw)).toString();
  }
}