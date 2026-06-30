import 'dart:math';

class GossipProtection {
  final Set<String> cache = {};
  final Random _rand = Random();

  bool shouldForward(String messageId) {
    if (cache.contains(messageId)) return false;

    cache.add(messageId);

    // probabilistic forwarding (reduce spam)
    return _rand.nextDouble() > 0.15;
  }

  void cleanup() {
    if (cache.length > 5000) {
      cache.clear();
    }
  }
}