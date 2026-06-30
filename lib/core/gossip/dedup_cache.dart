class DedupCache {
  final Set<String> _cache = {};

  bool seen(String id) {
    if (_cache.contains(id)) return true;
    _cache.add(id);
    return false;
  }

  void clear() {
    _cache.clear();
  }
}