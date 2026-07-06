import '../../../objectbox.g.dart';
import '../entities/profile_entity.dart';
import '../entities/peer_profile_entity.dart';
import '../objectbox/store.dart';

class ProfileRepository {
  final ObjectBoxStore _db;
  Box<ProfileEntity>? _profileBoxCached;
  Box<PeerProfileEntity>? _peerBoxCached;

  ProfileRepository(this._db);

  Box<ProfileEntity> get _profileBox => _profileBoxCached ??= _db.getBox<ProfileEntity>();
  Box<PeerProfileEntity> get _peerBox => _peerBoxCached ??= _db.getBox<PeerProfileEntity>();

  // ---------------- Mon profil (une seule ligne) ----------------

  ProfileEntity getOrCreateMine() {
    final all = _profileBox.getAll();
    if (all.isNotEmpty) return all.first;
    final fresh = ProfileEntity(updatedAt: DateTime.now().millisecondsSinceEpoch);
    fresh.id = _profileBox.put(fresh);
    return fresh;
  }

  void saveMine(ProfileEntity profile) {
    profile.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _profileBox.put(profile);
  }

  // ---------------- Profils reçus des pairs ----------------

  PeerProfileEntity? getPeerProfile(String peerId) {
    return _peerBox.query(PeerProfileEntity_.peerId.equals(peerId)).build().findFirst();
  }

  /// N'écrase l'entrée existante que si l'annonce reçue est PLUS RÉCENTE
  /// (protège contre un rejeu tardif qui écraserait une version à jour).
  /// Retourne `true` si une mise à jour a réellement eu lieu (utile pour
  /// ne notifier l'UI que quand quelque chose a vraiment changé).
  bool upsertPeerProfile({
    required String peerId,
    required String displayName,
    required String bio,
    required String photoBase64,
    required int updatedAt,
  }) {
    final existing = getPeerProfile(peerId);
    if (existing != null && existing.updatedAt >= updatedAt) return false;

    final entity = PeerProfileEntity(
      id: existing?.id ?? 0,
      peerId: peerId,
      displayName: displayName,
      bio: bio,
      photoBase64: photoBase64,
      updatedAt: updatedAt,
    );
    _peerBox.put(entity);
    return true;
  }

  List<PeerProfileEntity> allPeerProfiles() => _peerBox.getAll();
}
