import 'dart:convert';
import 'packet_model.dart';

class MessageCodec {
  static String encode(Packet packet) {
    return jsonEncode(packet.toJson());
  }

  static Packet decode(String raw) {
    final json = jsonDecode(raw);
    return Packet.fromJson(json);
  }
}