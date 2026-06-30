class TtlController {
  final Map<String, int> ttl = {};

  void add(String id, int value) {
    ttl[id] = value;
  }

  void tick() {
    ttl.removeWhere((key, value) => value <= 0);
    ttl.updateAll((key, value) => value - 1);
  }

  bool alive(String id) => ttl.containsKey(id);
}