class Packet {
  final String type;
  final String from;
  final String to;
  final Map<String, dynamic> payload;
  final int timestamp;

  Packet({
    required this.type,
    required this.from,
    required this.to,
    required this.payload,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    "type": type,
    "from": from,
    "to": to,
    "payload": payload,
    "timestamp": timestamp,
  };

  factory Packet.fromJson(Map<String, dynamic> json) {
    return Packet(
      type: json["type"],
      from: json["from"],
      to: json["to"],
      payload: Map<String, dynamic>.from(json["payload"]),
      timestamp: json["timestamp"],
    );
  }
}