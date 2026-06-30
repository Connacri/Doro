class GossipEngine {
  final Set<String> _seen = {};

  Function(Map<String, dynamic> data)? onBroadcast;

  void receive(String from, String raw) {
    final key = "$from:$raw.hashCode";

    if (_seen.contains(key)) return;
    _seen.add(key);

    final data = {
      "from": from,
      "payload": raw,
    };

    _forward(data);
  }

  void _forward(Map<String, dynamic> data) {
    onBroadcast?.call(data);
  }

  void broadcast(String from, Map<String, dynamic> data) {
    final encoded = data.toString();
    receive(from, encoded);
  }
}