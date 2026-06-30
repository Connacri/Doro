class Peer {
  final String id;
  final String address;
  final bool isTrusted;
  final DateTime lastSeen;

  Peer({
    required this.id,
    required this.address,
    this.isTrusted = false,
    required this.lastSeen,
  });

  Peer copyWith({
    bool? isTrusted,
    DateTime? lastSeen,
  }) {
    return Peer(
      id: id,
      address: address,
      isTrusted: isTrusted ?? this.isTrusted,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}