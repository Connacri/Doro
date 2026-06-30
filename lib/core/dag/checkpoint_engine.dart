class CheckpointEngine {
  final Set<String> finalBlocks = {};

  void confirm(String txId, int confirmations) {
    if (confirmations >= 5) {
      finalBlocks.add(txId);
    }
  }

  bool isFinal(String txId) {
    return finalBlocks.contains(txId);
  }
}