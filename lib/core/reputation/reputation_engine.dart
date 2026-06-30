class ReputationEngine {
  final Map<String, double> _scores = {};

  void increase(String nodeId) {
    _scores[nodeId] = (_scores[nodeId] ?? 1) + 1;
  }

  void decrease(String nodeId) {
    _scores[nodeId] = (_scores[nodeId] ?? 1) - 2;
  }

  double weight(String nodeId) {
    return (_scores[nodeId] ?? 1).clamp(1, 100);
  }

  bool isTrusted(String nodeId) {
    return weight(nodeId) > 15;
  }
}