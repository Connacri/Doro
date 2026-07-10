// lib/features/profile/profile_provider.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import '../../core/supabase/profile_service.dart';
import '../../core/utils/image_compress.dart';
import '../../core/utils/logger.dart';

/// Profil (nom, bio, avatar, couverture) — piloté par Supabase, avec
/// dégradation gracieuse : tant que [SupabaseBootstrap] n'est pas prêt
/// (config manquante, réseau lent/en échec), [available] est `false`
/// et les actions sont des no-ops silencieux. C'est à l'UI d'afficher
/// un état "indisponible" plutôt que de bloquer toute l'app.
class ProfileProvider extends ChangeNotifier {
  final SupabaseBootstrap bootstrap;
  final String nodeId;

  ProfileService? _service;
  SupabaseClient? _supabase;
  bool get available => _service != null && _supabase != null;
  String? get unavailableReason => bootstrap.errorMessage;

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

  ProfileProvider(this.bootstrap, this.nodeId) {
    bootstrap.addListener(_onBootstrapChange);
    _onBootstrapChange();
  }

  String get myAddress => nodeId;

  void _onBootstrapChange() {
    final newService = bootstrap.profileService;
    final newSupabase = newService?.client;
    if (newService == _service) {
      notifyListeners();
      return;
    }
    _channel?.unsubscribe();
    _channel = null;
    _service = newService;
    _supabase = newSupabase;
    if (_service != null && _supabase != null) {
      _loadMine();
      _subscribeRealtime();
    }
    notifyListeners();
  }

  Future<void> _loadMine() async {
    final service = _service;
    if (service == null) return;
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
    final supabase = _supabase;
    if (supabase == null) return;
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
            final service = _service;
            if (pubkey == nodeId && service != null) {
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
    final service = _service;
    if (service == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final rawBytes = result.files.first.bytes;
    if (rawBytes == null) return;
    try {
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
    final service = _service;
    if (service == null) return;
    await service.deleteAvatar();
    _avatarUrl = null;
    _mine = await service.getMyProfile();
    notifyListeners();
  }

  /// Photo de couverture façon Facebook, en bannière au-dessus du profil.
  Future<void> pickCover() async {
    final service = _service;
    if (service == null) return;
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
    final service = _service;
    if (service == null) return;
    await service.deleteCover();
    _coverUrl = null;
    _mine = await service.getMyProfile();
    notifyListeners();
  }

  Future<void> saveNameAndBio({required String name, required String bio}) async {
    final service = _service;
    if (service == null) return;
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

  Future<DateTime?> requestAccountDeletion() async {
    final service = _service;
    if (service == null) return null;
    final date = await service.requestAccountDeletion();
    _deletionStatus = DeletionStatus(date);
    notifyListeners();
    return date;
  }

  Future<bool> cancelAccountDeletion() async {
    final service = _service;
    if (service == null) return false;
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
    final service = _service;
    if (service == null) return null;
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
    final service = _service;
    final profile = _peerCache[peerId];
    final path = profile?['avatar_url'] as String?;
    _peerAvatarUrlCache[peerId] = null; // évite les résolutions en boucle pendant l'attente
    if (path != null && service != null) {
      service.resolveAvatarUrl(path).then((url) {
        _peerAvatarUrlCache[peerId] = url;
        notifyListeners();
      });
    }
    return null;
  }

  @override
  void dispose() {
    bootstrap.removeListener(_onBootstrapChange);
    _channel?.unsubscribe();
    super.dispose();
  }
}
