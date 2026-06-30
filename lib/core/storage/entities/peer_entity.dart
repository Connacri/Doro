import 'package:objectbox/objectbox.dart';

@Entity()
class PeerEntity {
  int id = 0;

  String peerId;
  String address;
  bool trusted;
  int lastSeen;

  PeerEntity({
    required this.peerId,
    required this.address,
    this.trusted = false,
    required this.lastSeen,
  });
}