class ReputationScore {
  final Map<String, double> _scores = {};

  void increase(String node) {
    _scores[node] = (_scores[node] ?? 1) + 1;
  }

  void decrease(String node) {
    _scores[node] = (_scores[node] ?? 1) - 2;
  }

  double get(String node) {
    return _scores[node] ?? 1;
  }

  bool trusted(String node) {
    return get(node) > 10;
  }
}