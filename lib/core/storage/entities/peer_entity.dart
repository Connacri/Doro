import 'package:objectbox/objectbox.dart';

@Entity()
class PeerEntity {
  int id = 0;

  @Index()
  final String peerId;
  final String address;
  final bool trusted;
  final int lastSeen;

  PeerEntity({
    this.id = 0,
    required this.peerId,
    required this.address,
    this.trusted = false,
    required this.lastSeen,
  });
}
