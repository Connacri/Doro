class SybilProtection {
  final Map<String, int> nodeScores = {};

  void registerNode(String nodeId) {
    nodeScores[nodeId] = 0;
  }

  void increaseTrust(String nodeId) {
    nodeScores[nodeId] = (nodeScores[nodeId] ?? 0) + 1;
  }

  void decreaseTrust(String nodeId) {
    nodeScores[nodeId] = (nodeScores[nodeId] ?? 0) - 2;
  }

  bool isTrusted(String nodeId) {
    return (nodeScores[nodeId] ?? 0) >= 10;
  }

  bool isBlocked(String nodeId) {
    return (nodeScores[nodeId] ?? 0) < -5;
  }
}