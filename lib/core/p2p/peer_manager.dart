import '../security/sybil_protection.dart';
import 'peer_model.dart';
import 'webrtc_engine.dart';

class PeerManager {
  final WebRTCNetworkEngine engine;
  final SybilProtection sybil;

  PeerManager({
    required this.engine,
    required this.sybil,
  });

  Future<void> addPeer(Peer peer) async {
    if (sybil.isBlocked(peer.id)) return;

    await engine.connectPeer(peer);
    sybil.increaseTrust(peer.id);
  }

  void removePeer(String peerId) {
    engine.removePeer(peerId);
    sybil.decreaseTrust(peerId);
  }

  void broadcastTx(Map<String, dynamic> tx) {
    engine.broadcast(tx);
  }
}