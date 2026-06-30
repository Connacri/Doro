import '../p2p/webrtc_engine.dart';
import '../gossip/gossip_engine.dart';
import '../sync/sync_engine.dart';

class NetworkCore {
  final WebRTCNetworkEngine p2p;
  final GossipEngine gossip;
  final SyncEngine sync;

  bool isOnline = false;

  NetworkCore({
    required this.p2p,
    required this.gossip,
    required this.sync,
  });

  void start() {
    isOnline = true;

    p2p.onMessage = (from, msg) {
      gossip.receive(from, msg);
    };

    gossip.onBroadcast = (data) {
      p2p.broadcast(data);
    };
  }

  void stop() {
    isOnline = false;
  }
}