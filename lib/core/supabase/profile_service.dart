// lib/core/supabase/profile_service.dart
//
// CRUD du profil (nom, avatar, photo de couverture) + cycle de
// suppression de compte façon Facebook :
//   - requestDeletion() programme la purge dans 30 jours et renvoie
//     la date, à afficher dans un bandeau ("Ton compte sera supprimé
//     le ... — connecte-toi avant pour annuler").
//   - au prochain login, appelle deletionStatus() : si un compte est
//     programmé pour suppression, propose cancelDeletion().
//   - la purge réelle (lignes DB + fichiers des buckets avatars/covers
//     + le user auth) est faite côté serveur par pg_cron, jamais par
//     le client — voir purge_deleted_accounts() dans la migration.
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeletionStatus {
  final DateTime? scheduledFor;
  bool get isPendingDeletion => scheduledFor != null && scheduledFor!.isAfter(DateTime.now());
  DeletionStatus(this.scheduledFor);
}

class ProfileService {
  final SupabaseClient _client;
  final String nodeId; // = public_key

  SupabaseClient get client => _client;

  ProfileService(this._client, this.nodeId);

  // ---------------------------------------------------------------
  // CRUD profil
  // ---------------------------------------------------------------

  Future<Map<String, dynamic>?> getMyProfile() async {
    return await _client.from('profiles').select().eq('public_key', nodeId).maybeSingle();
  }

  /// Profil PUBLIC d'un pair quelconque (nom/bio/avatar/cover) — comme
  /// avant en P2P, le profil est une information publique par nature,
  /// visible de tout utilisateur authentifié (cf. policy
  /// `profiles_select_all_authenticated`).
  Future<Map<String, dynamic>?> getProfile(String publicKey) async {
    return await _client.from('profiles').select().eq('public_key', publicKey).maybeSingle();
  }

  Future<void> updateDisplayName(String name) async {
    await _client.from('profiles').update({'display_name': name}).eq('public_key', nodeId);
  }

  Future<void> updateBio(String bio) async {
    await _client.from('profiles').update({'bio': bio}).eq('public_key', nodeId);
  }

  /// Upload/replace la photo de profil. [bytes] = contenu du fichier
  /// déjà compressé côté app (recommandé: ~512px, jpeg qualité ~80).
  Future<String> uploadAvatar(Uint8List bytes, {String ext = 'jpg'}) async {
    final path = '$nodeId/avatar.$ext';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, cacheControl: '3600'),
        );
    final signedUrl = await _client.storage.from('avatars').createSignedUrl(path, 60 * 60 * 24 * 7);
    await _client.from('profiles').update({'avatar_url': path}).eq('public_key', nodeId);
    return signedUrl;
  }

  Future<void> deleteAvatar() async {
    final row = await getMyProfile();
    final path = row?['avatar_url'] as String?;
    if (path != null) {
      await _client.storage.from('avatars').remove([path]);
    }
    await _client.from('profiles').update({'avatar_url': null}).eq('public_key', nodeId);
  }

  /// Upload/replace la photo de couverture (bannière façon Facebook).
  Future<String> uploadCover(Uint8List bytes, {String ext = 'jpg'}) async {
    final path = '$nodeId/cover.$ext';
    await _client.storage.from('covers').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, cacheControl: '3600'),
        );
    final signedUrl = await _client.storage.from('covers').createSignedUrl(path, 60 * 60 * 24 * 7);
    await _client.from('profiles').update({'cover_url': path}).eq('public_key', nodeId);
    return signedUrl;
  }

  Future<void> deleteCover() async {
    final row = await getMyProfile();
    final path = row?['cover_url'] as String?;
    if (path != null) {
      await _client.storage.from('covers').remove([path]);
    }
    await _client.from('profiles').update({'cover_url': null}).eq('public_key', nodeId);
  }

  /// Résout une URL signée temporaire à partir du chemin stocké en base
  /// (les buckets sont privés : pas d'URL publique permanente).
  Future<String?> resolveAvatarUrl(String? storedPath) async {
    if (storedPath == null) return null;
    return _client.storage.from('avatars').createSignedUrl(storedPath, 60 * 60 * 24 * 7);
  }

  Future<String?> resolveCoverUrl(String? storedPath) async {
    if (storedPath == null) return null;
    return _client.storage.from('covers').createSignedUrl(storedPath, 60 * 60 * 24 * 7);
  }

  // ---------------------------------------------------------------
  // Suppression de compte façon Facebook (30 jours de grâce)
  // ---------------------------------------------------------------

  /// Programme la suppression définitive dans 30 jours. Renvoie la date
  /// à afficher : "Ton compte sera supprimé le {date}. Reconnecte-toi
  /// avant cette date pour annuler."
  Future<DateTime> requestAccountDeletion() async {
    final res = await _client.rpc('request_account_deletion');
    return DateTime.parse(res as String);
  }

  /// À appeler au login : si un compte est programmé pour suppression,
  /// affiche le bandeau de rappel façon Facebook et propose d'annuler.
  Future<DeletionStatus> deletionStatus() async {
    final row = await getMyProfile();
    final raw = row?['deleted_at'] as String?;
    return DeletionStatus(raw != null ? DateTime.parse(raw) : null);
  }

  /// Annule la suppression programmée (uniquement possible avant la
  /// date de purge — après, le compte et ses données n'existent plus).
  Future<bool> cancelAccountDeletion() async {
    final res = await _client.rpc('cancel_account_deletion');
    return res as bool;
  }
}
