class DoubleSpendChecker {
  final Set<String> spent = {};

  bool isSpent(String sender) {
    return spent.contains(sender);
  }

  void markSpent(String sender) {
    spent.add(sender);
  }

  bool validate(String sender) {
    if (isSpent(sender)) return false;

    markSpent(sender);
    return true;
  }
}