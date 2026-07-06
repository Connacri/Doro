import '../security/sybil_protection.dart';
import '../storage/objectbox/store.dart';
import 'peer_model.dart';
import 'webrtc_engine.dart';

class PeerManager {
  final WebRTCNetworkEngine engine;
  final SybilProtection sybil;

  PeerManager(ObjectBoxStore db, {
    required this.engine,
    SybilProtection? sybil,
  }) : sybil = sybil ?? SybilProtection();

  Future<void> addPeer(Peer peer) async {
    if (sybil.isBlocked(peer.id)) return;
    await engine.createOffer(peer.id);
    sybil.increaseTrust(peer.id);
  }

  /// À appeler dès qu'on COMMENCE une négociation avec ce pair (offre
  /// envoyée ou reçue) — augmente sa réputation de base sans jamais le
  /// marquer "connecté" dans `engine.peers`. Cette dernière liste ne doit
  /// refléter QUE des canaux de données réellement ouverts (voir
  /// `WebRTCNetworkEngine._registerOnceChannelOpen`) ; la confondre avec
  /// "une négociation a démarré" est ce qui causait un statut "connecté"
  /// trompeur avant que ICE n'ait réellement abouti.
  void markNegotiating(String peerId) {
    if (sybil.isBlocked(peerId)) return;
    sybil.increaseTrust(peerId);
  }

  void removePeer(String peerId) {
    engine.removePeer(peerId);
    sybil.decreaseTrust(peerId);
  }

  bool isBlocked(String peerId) => sybil.isBlocked(peerId);

  void broadcastTx(Map<String, dynamic> tx) {
    engine.broadcast(tx);
  }
}
