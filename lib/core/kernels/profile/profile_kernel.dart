import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../p2p/webrtc_engine.dart';
import '../../security/sybil_protection.dart';
import '../../storage/repositories/profile_repository.dart';
import '../../utils/logger.dart';

/// Diffuse mon profil (nom/bio/photo) à tous les pairs connectés, et
/// reçoit/persiste ceux des autres — un profil est une information
/// PUBLIQUE par nature (comme le nodeId), donc annoncée à tout pair
/// connecté, pas seulement aux amis.
class ProfileKernel {
  final String nodeId;
  final WebRTCNetworkEngine p2p;
  final ProfileRepository repo;
  final SybilProtection sybil;

  /// Taille max acceptée pour une photo encodée en base64 — au-delà,
  /// l'annonce est rejetée. Une vraie photo de profil raisonnable
  /// (miniature ~256x256 JPEG compressée) tient largement dans cette
  /// limite ; un dépassement systématique signale un pair qui essaie
  /// d'utiliser le canal de profil comme vecteur de spam/DoS mémoire.
  static const int _maxPhotoBase64Chars = 200000; // ~150 Ko décodés

  /// Un pair honnête ne change pas son profil en boucle — au-delà de ce
  /// débit, on considère l'annonce comme du spam plutôt qu'une vraie
  /// mise à jour de profil.
  final Map<String, DateTime> _lastAnnounceAt = {};
  final Map<String, int> _announceCountThisWindow = {};
  static const int _maxAnnouncesPerMinute = 3;

  final _profileChangedController = StreamController<String>.broadcast();
  /// Émet le `peerId` dont le profil vient d'être mis à jour localement —
  /// l'UI s'y abonne pour rafraîchir sans polling.
  Stream<String> get profileChanges => _profileChangedController.stream;

  ProfileKernel({
    required this.nodeId,
    required this.p2p,
    required this.repo,
    SybilProtection? sybil,
  }) : sybil = sybil ?? SybilProtection() {
    p2p.messages.listen((msg) {
      final data = msg.data;
      if (data is Map<String, dynamic> && data["type"] == "profile") {
        _handleIncomingProfile(msg.from, data);
      }
    });
  }

  /// À appeler dès qu'un canal WebRTC s'ouvre avec un pair — il reçoit
  /// alors mon profil actuel sans avoir à le demander explicitement.
  Future<void> announceTo(String peerId) async {
    final wire = await _toWire();
    p2p.sendToPeer(peerId, wire);
  }

  /// Diffuse mon profil à tout le monde immédiatement — à appeler après
  /// modification (nouveau nom/bio/photo).
  Future<void> broadcastMine() async {
    final wire = await _toWire();
    p2p.broadcast(wire);
  }

  /// `photoPath` doit déjà pointer vers une image redimensionnée/compressée
  /// par la couche UI (voir `ProfileProvider`) — le kernel ne fait QUE lire
  /// et encoder en base64, jamais de traitement d'image ici (pas la bonne
  /// couche pour ça, et évite de dupliquer une dépendance de décodage
  /// d'image dans le cœur réseau).
  Future<Map<String, dynamic>> _toWire() async {
    final mine = repo.getOrCreateMine();
    var photoBase64 = "";
    if (mine.photoPath.isNotEmpty) {
      try {
        final file = File(mine.photoPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final encoded = base64Encode(bytes);
          if (encoded.length <= _maxPhotoBase64Chars) {
            photoBase64 = encoded;
          } else {
            Logger.warn("Photo de profil locale trop volumineuse — non diffusée");
          }
        }
      } catch (e) {
        Logger.warn("Lecture photo de profil impossible : $e");
      }
    }

    return {
      "type": "profile",
      "from": nodeId,
      "name": mine.displayName,
      "bio": mine.bio,
      "photo": photoBase64,
      "updatedAt": mine.updatedAt,
    };
  }

  bool _admitAnnounce(String peerId) {
    if (sybil.isBlocked(peerId)) return false;
    final now = DateTime.now();
    final last = _lastAnnounceAt[peerId];
    if (last == null || now.difference(last).inMinutes >= 1) {
      _lastAnnounceAt[peerId] = now;
      _announceCountThisWindow[peerId] = 0;
    }
    final count = (_announceCountThisWindow[peerId] ?? 0) + 1;
    _announceCountThisWindow[peerId] = count;
    if (count > _maxAnnouncesPerMinute) {
      sybil.decreaseTrust(peerId);
      return false;
    }
    return true;
  }

  void _handleIncomingProfile(String fromPeer, Map<String, dynamic> data) {
    final from = data["from"] as String?;
    if (from == null || from != fromPeer || from == nodeId) return;

    if (!_admitAnnounce(fromPeer)) {
      Logger.warn("Annonces de profil trop fréquentes de $fromPeer — ignorées");
      return;
    }

    final photo = (data["photo"] as String?) ?? "";
    if (photo.length > _maxPhotoBase64Chars) {
      Logger.warn("Photo de profil trop volumineuse ignorée pour $fromPeer");
      sybil.decreaseTrust(fromPeer);
      return;
    }

    final updated = repo.upsertPeerProfile(
      peerId: from,
      displayName: (data["name"] as String?) ?? "",
      bio: (data["bio"] as String?) ?? "",
      photoBase64: photo,
      updatedAt: (data["updatedAt"] as int?) ?? 0,
    );

    if (updated) _profileChangedController.add(from);
  }

  void dispose() {
    _profileChangedController.close();
  }
}
