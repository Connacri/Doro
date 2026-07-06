import 'dart:async';
import 'dart:convert';
import '../utils/logger.dart';
import 'peer_connection.dart';
import 'peer_model.dart';

class WebRTCNetworkEngine {
  final String nodeId;
  final Map<String, PeerConnection> _connections = {};
  final Map<String, Peer> peers = {};

  final _messageController = StreamController<({String from, dynamic data})>.broadcast();
  Stream<({String from, dynamic data})> get messages => _messageController.stream;

  void Function(String peerId)? onPeerConnected;
  void Function(String peerId)? onPeerDisconnected;
  void Function(String peerId, Map<String, dynamic> candidate)? onIceCandidate;
  void Function(String peerId)? onChannelOpen;

  WebRTCNetworkEngine(this.nodeId);

  void registerPeer(Peer peer) {
    final isNew = !peers.containsKey(peer.id);
    peers[peer.id] = peer;
    if (isNew) onPeerConnected?.call(peer.id);
  }

  /// N'ajoute `peerId` à `peers` (donc à la liste "connecté" vue par
  /// l'UI, et à ce qui rend `sendToPeer`/`broadcast` réellement capables
  /// de livrer) que lorsque le canal de données WebRTC est VRAIMENT
  /// ouvert — jamais dès l'échange SDP offer/answer. Avant ce correctif,
  /// le côté qui ACCEPTAIT une offre était marqué "connecté"
  /// immédiatement (avant même la négociation ICE), tandis que le côté
  /// qui ENVOYAIT l'offre n'était jamais ajouté à cette liste du tout —
  /// ni l'un ni l'autre ne reflétait la réalité, ce qui donnait
  /// l'impression trompeuse qu'un pair "découvert" était joignable alors
  /// que rien ne pouvait réellement transiter tant que ICE n'avait pas
  /// abouti.
  void _registerOnceChannelOpen(String peerId) {
    registerPeer(Peer(id: peerId, address: "", lastSeen: DateTime.now()));
  }

  Future<Map<String, dynamic>?> createOffer(String peerId) async {
    if (_connections.containsKey(peerId)) return null;
    final conn = PeerConnection();
    await conn.init();

    conn.onMessage = (msg) {
      try {
        final data = jsonDecode(msg);
        _messageController.add((from: peerId, data: data));
      } catch (e) {
        Logger.warn("Failed to decode message from $peerId: $e");
      }
    };
    conn.onDisconnect(() => removePeer(peerId));
    conn.onIceCandidate((candidate) => onIceCandidate?.call(peerId, candidate));
    conn.onChannelOpen(() {
      _registerOnceChannelOpen(peerId);
      onChannelOpen?.call(peerId);
    });

    await conn.createChannel();
    final offer = await conn.createOffer();
    _connections[peerId] = conn;
    return offer;
  }

  Future<void> handleAnswer(String peerId, dynamic sdp) async {
    final conn = _connections[peerId];
    if (conn == null) return;
    await conn.setRemoteDescription(sdp);
  }

  Future<Map<String, dynamic>?> acceptConnection(String peerId, dynamic sdp) async {
    if (_connections.containsKey(peerId)) return null;
    final conn = PeerConnection();
    await conn.init();

    conn.onMessage = (msg) {
      try {
        final data = jsonDecode(msg);
        _messageController.add((from: peerId, data: data));
      } catch (e) {
        Logger.warn("Failed to decode message from $peerId: $e");
      }
    };
    conn.onDisconnect(() => removePeer(peerId));
    conn.onIceCandidate((candidate) => onIceCandidate?.call(peerId, candidate));
    conn.onChannelOpen(() {
      _registerOnceChannelOpen(peerId);
      onChannelOpen?.call(peerId);
    });

    await conn.setRemoteDescription(sdp);
    final answer = await conn.createAnswer();
    _connections[peerId] = conn;
    return answer;
  }

  Future<void> handleIce(String peerId, dynamic candidate) async {
    final conn = _connections[peerId];
    if (conn == null) return;
    await conn.addIceCandidate(candidate);
  }

  /// Retourne `true` si le message a réellement été envoyé sur le canal
  /// WebRTC de ce pair, `false` sinon (pair inconnu ou canal pas encore
  /// ouvert). Ne JAMAIS ignorer cette valeur côté appelant — un `false`
  /// veut dire que le message est perdu si personne ne le renvoie.
  bool sendToPeer(String peerId, Map<String, dynamic> data) {
    final conn = _connections[peerId];
    if (conn == null) return false;
    return conn.send(jsonEncode(data));
  }

  /// Une connexion (en cours ou établie) existe-t-elle déjà pour ce pair ?
  /// Évite les doubles connexions quand les deux pairs s'initient
  /// simultanément.
  bool isConnectedTo(String peerId) => _connections.containsKey(peerId);

  /// Le canal de données vers ce pair est-il actuellement ouvert et prêt
  /// à transmettre (par opposition à "en cours de négociation ICE").
  bool isPeerChannelOpen(String peerId) => _connections[peerId]?.isOpen ?? false;

  void broadcast(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    for (final conn in _connections.values) {
      conn.send(encoded);
    }
  }

  void removePeer(String peerId) {
    _connections[peerId]?.close();
    _connections.remove(peerId);
    final existed = peers.remove(peerId) != null;
    if (existed) onPeerDisconnected?.call(peerId);
  }

  Future<void> dispose() async {
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    peers.clear();
    await _messageController.close();
  }
}
