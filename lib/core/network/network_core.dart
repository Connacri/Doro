import '../p2p/webrtc_engine.dart';
import '../gossip/gossip_engine.dart';
import '../sync/sync_engine.dart';
import '../dag/dag_engine.dart';

class NetworkCore {
  final WebRTCNetworkEngine p2p;
  final GossipEngine gossip;
  final SyncEngine sync;
  final DagEngine dag;

  NetworkCore({
    required this.p2p,
    required this.gossip,
    required this.sync,
    required this.dag,
  });

  void start() {
    // P2P → Gossip
    p2p.onMessage = (from, msg) {
      gossip.receive(from, msg);
    };

    // Gossip → DAG
    gossip.onBroadcast = (data) {
      dag.addFromNetwork(data);
    };

    // DAG → Sync
    dag.onCommit = (tx) {
      sync.push(tx);
    };
  }
}