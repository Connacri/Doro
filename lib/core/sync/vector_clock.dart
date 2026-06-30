class VectorClock {
  final Map<String, int> clock = {};

  void tick(String nodeId) {
    clock[nodeId] = (clock[nodeId] ?? 0) + 1;
  }

  bool happensBefore(VectorClock other) {
    for (final key in clock.keys) {
      if ((clock[key] ?? 0) > (other.clock[key] ?? 0)) {
        return false;
      }
    }
    return true;
  }

  Map<String, int> export() => clock;
}