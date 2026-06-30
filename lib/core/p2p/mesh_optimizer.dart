class MeshOptimizer {
  final Map<String, int> latency = {};

  void updateLatency(String peer, int ms) {
    latency[peer] = ms;
  }

  List<String> bestPeers() {
    final sorted = latency.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return sorted.take(5).map((e) => e.key).toList();
  }
}