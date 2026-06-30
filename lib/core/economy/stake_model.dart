class Stake {
  final String nodeId;
  BigInt amount;
  int lockedUntil;

  Stake({
    required this.nodeId,
    required this.amount,
    required this.lockedUntil,
  });

  bool isActive(int now) => now < lockedUntil;
}