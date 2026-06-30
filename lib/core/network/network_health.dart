class NetworkHealth {
  final Map<String, DateTime> lastSeen = {};

  void ping(String nodeId) {
    lastSeen[nodeId] = DateTime.now();
  }

  bool isAlive(String nodeId) {
    final last = lastSeen[nodeId];
    if (last == null) return false;

    return DateTime.now().difference(last).inSeconds < 30;
  }

  List<String> deadNodes() {
    return lastSeen.entries
        .where((e) =>
    DateTime.now().difference(e.value).inSeconds > 60)
        .map((e) => e.key)
        .toList();
  }
}