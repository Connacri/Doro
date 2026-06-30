import 'dart:convert';

class GossipEngine {
  final Set<String> _seen = {};
  
  // Callback to send message to peers
  Function(String raw)? onForward;
  // Callback when a new message is received and processed
  Function(Map<String, dynamic> data)? onMessage;

  void receive(String from, String raw) {
    final hash = raw.hashCode.toString();

    if (_seen.contains(hash)) return;
    _seen.add(hash);

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      onMessage?.call(data);
      
      // Forward to other peers
      onForward?.call(raw);
    } catch (e) {
      print("Error decoding gossip message: $e");
    }
  }

  void broadcast(Map<String, dynamic> data) {
    final raw = jsonEncode(data);
    _seen.add(raw.hashCode.toString());
    onForward?.call(raw);
  }
}
