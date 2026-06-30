import 'dart:convert';
import 'package:crypto/crypto.dart';

class DeviceIdentity {
  final String deviceId;
  final String pubKey;

  DeviceIdentity({
    required this.deviceId,
    required this.pubKey,
  });

  String fingerprint() {
    final raw = "$deviceId:$pubKey";
    return sha256.convert(utf8.encode(raw)).toString();
  }
}