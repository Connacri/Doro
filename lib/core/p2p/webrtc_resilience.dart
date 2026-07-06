import 'dart:async';
import '../utils/logger.dart';

/// Helper to manage WebRTC connection retries and monitoring.
class WebRTCResilience {
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 5);

  final Map<String, int> _retryCounts = {};
  final Map<String, Timer> _retryTimers = {};

  void reset(String peerId) {
    _retryCounts.remove(peerId);
    _retryTimers[peerId]?.cancel();
    _retryTimers.remove(peerId);
  }

  bool canRetry(String peerId) {
    final count = _retryCounts[peerId] ?? 0;
    return count < maxRetries;
  }

  void incrementRetry(String peerId) {
    _retryCounts[peerId] = (_retryCounts[peerId] ?? 0) + 1;
  }

  void scheduleRetry(String peerId, Function() onRetry) {
    _retryTimers[peerId]?.cancel();
    _retryTimers[peerId] = Timer(retryDelay, () {
      Logger.info("Resilience: Retrying connection to $peerId (attempt ${_retryCounts[peerId]})");
      onRetry();
    });
  }

  void dispose() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
  }
}
