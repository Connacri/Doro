// lib/features/profile/profile_provider.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/profile_service.dart';
import '../../core/utils/image_compress.dart';
import '../../core/utils/logger.dart';

/// Profil (nom, bio, avatar, couverture) — remplace l'ancienne diffusion
/// P2P par Supabase : `profiles` est une table PUBLIQUE en lecture pour
/// tout utilisateur authentifié (même sémantique qu'avant : un profil
/// n'est pas une info privée), avec Realtime pour recevoir les mises à
/// jour des autres pairs sans polling.
class ProfileProvider extends ChangeNotifier {
  final ProfileService service;
  final SupabaseClient supabase;
  final String nodeId;

  Map<String, dynamic>? _mine;
  Map<String, dynamic>? get mine => _mine;

  String? _avatarUrl;
  String? _coverUrl;
  String? get avatarUrl => _avatarUrl;
  String? get coverUrl => _coverUrl;

  bool _saving = false;
  bool get saving => _saving;

  DeletionStatus? _deletionStatus;
  DeletionStatus? get deletionStatus => _deletionStatus;

  final Map<String, Map<String, dynamic>> _peerCache = {};
  final Map<String, String?> _peerAvatarUrlCache = {};

  RealtimeChannel? _channel;

  ProfileProvider(this.service, this.supabase, this.nodeId) {
    _loadMine();
    _subscribeRealtime();
  }

  String get myAddress => nodeId;

  Future<void> _loadMine() async {
    try {
      _mine = await service.getMyProfile();
      _avatarUrl = await service.resolveAvatarUrl(_mine?['avatar_url'] as String?);
      _coverUrl = await service.resolveCoverUrl(_mine?['cover_url'] as String?);
      _deletionStatus = await service.deletionStatus();
      notifyListeners();
    } catch (e) {
      Logger.error("ProfileProvider: chargement du profil impossible : $e");
    }
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('profiles:all')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final row = payload.newRecord;
            final pubkey = row['public_key'] as String?;
            if (pubkey == null) return;
            _peerCache[pubkey] = row;
            _peerAvatarUrlCache.remove(pubkey); // invalide le cache d'URL signée
            if (pubkey == nodeId) {
              _mine = row;
              service.resolveAvatarUrl(row['avatar_url'] as String?).then((u) {
                _avatarUrl = u;
                notifyListeners();
              });
              service.resolveCoverUrl(row['cover_url'] as String?).then((u) {
                _coverUrl = u;
                notifyListeners();
              });
            }
            notifyListeners();
          },
        )
        .subscribe();
  }

  // ---------------- Mon profil ----------------

  Future<void> pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final rawBytes = result.files.first.bytes;
    if (rawBytes == null) return;
    try {
      // Redimensionnée/recompressée en JPEG dans un isolate séparé —
      // évite d'uploader une photo brute de plusieurs Mo et de bloquer
      // l'UI le temps du traitement. La sortie est toujours du JPEG,
      // quel que soit le format d'origine.
      final compressed = await ImageCompressor.compressAvatar(rawBytes);
      _avatarUrl = await service.uploadAvatar(compressed, ext: 'jpg');
      _mine = await service.getMyProfile();
      notifyListeners();
    } catch (e) {
      Logger.error("Impossible de mettre à jour la photo de profil : $e");
      rethrow;
    }
  }

  Future<void> removeAvatar() async {
    await service.deleteAvatar();
    _avatarUrl = null;
    _mine = await service.getMyProfile();
    notifyListeners();
  }

  /// Photo de couverture façon Facebook, en bannière au-dessus du profil.
  Future<void> pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final rawBytes = result.files.first.bytes;
    if (rawBytes == null) return;
    try {
      final compressed = await ImageCompressor.compressCover(rawBytes);
      _coverUrl = await service.uploadCover(compressed, ext: 'jpg');
      _mine = await service.getMyProfile();
      notifyListeners();
    } catch (e) {
      Logger.error("Impossible de mettre à jour la photo de couverture : $e");
      rethrow;
    }
  }

  Future<void> removeCover() async {
    await service.deleteCover();
    _coverUrl = null;
    _mine = await service.getMyProfile();
    notifyListeners();
  }

  Future<void> saveNameAndBio({required String name, required String bio}) async {
    _saving = true;
    notifyListeners();
    try {
      await service.updateDisplayName(name.trim());
      await service.updateBio(bio.trim());
      _mine = await service.getMyProfile();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ---------------- Suppression de compte (façon Facebook) ----------------

  Future<DateTime> requestAccountDeletion() async {
    final date = await service.requestAccountDeletion();
    _deletionStatus = DeletionStatus(date);
    notifyListeners();
    return date;
  }

  Future<bool> cancelAccountDeletion() async {
    final ok = await service.cancelAccountDeletion();
    if (ok) {
      _deletionStatus = DeletionStatus(null);
      notifyListeners();
    }
    return ok;
  }

  // ---------------- Profils des pairs ----------------

  /// Renvoie le profil en cache s'il existe déjà (Realtime le tient à
  /// jour) ; sinon lance une récupération asynchrone et notifie une fois
  /// arrivée.
  Map<String, dynamic>? peerProfile(String peerId) {
    final cached = _peerCache[peerId];
    if (cached != null) return cached;
    service.getProfile(peerId).then((row) {
      if (row != null) {
        _peerCache[peerId] = row;
        notifyListeners();
      }
    });
    return null;
  }

  /// URL signée (avatar) pour un pair — résolue paresseusement et mise
  /// en cache le temps de sa validité (7 jours).
  String? peerAvatarUrl(String peerId) {
    if (_peerAvatarUrlCache.containsKey(peerId)) return _peerAvatarUrlCache[peerId];
    final profile = _peerCache[peerId];
    final path = profile?['avatar_url'] as String?;
    _peerAvatarUrlCache[peerId] = null; // évite les résolutions en boucle pendant l'attente
    if (path != null) {
      service.resolveAvatarUrl(path).then((url) {
        _peerAvatarUrlCache[peerId] = url;
        notifyListeners();
      });
    }
    return null;
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}
