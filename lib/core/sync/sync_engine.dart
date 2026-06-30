import '../dag/dag_engine.dart';
import '../dag/transaction_model.dart';
import '../p2p/webrtc_engine.dart';
import 'offline_queue.dart';
import 'state_reconciliation.dart';

class SyncEngine {
  final DagEngine dag;
  final WebRTCNetworkEngine network;
  final OfflineQueue queue;
  final StateReconciliation merger;

  SyncEngine({
    required this.dag,
    required this.network,
    required this.queue,
    required this.merger,
  });

  /// Appelé quand une transaction est créée offline
  void addOffline(Transaction tx) {
    queue.add(tx);
  }

  /// Sync avec réseau
  void syncWithNetwork(List<Transaction> remoteTxs) {
    final localTxs = dag.all;

    final merged = merger.merge(localTxs, remoteTxs);

    for (final tx in merged) {
      dag.add(tx);
    }
  }

  /// Flush offline queue vers réseau
  void flushOffline() {
    final txs = queue.drain();

    for (final tx in txs) {
      network.broadcast({
        "type": "tx",
        "data": tx.toJson(),
      });
    }
  }
}