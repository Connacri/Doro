import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/p2p/p2p_node.dart';
import '../../core/storage/entities/peer_profile_entity.dart';
import '../../core/storage/entities/profile_entity.dart';
import '../../core/storage/repositories/profile_repository.dart';
import '../../core/utils/logger.dart';

class ProfileProvider extends ChangeNotifier {
  final ProfileRepository repo;
  final P2PNode? node;
  final ImagePicker _picker = ImagePicker();

  ProfileEntity? _mine;
  ProfileEntity? get mine => _mine;

  bool _saving = false;
  bool get saving => _saving;

  ProfileProvider(this.repo, {this.node}) {
    _mine = repo.getOrCreateMine();
    node?.profileChanges.listen((_) => notifyListeners());
  }

  String get myAddress => node?.nodeId ?? "";

  /// Choisit une image (galerie ou caméra), la redimensionne/compresse
  /// DIRECTEMENT via `image_picker` (pas besoin d'une lib de traitement
  /// d'image séparée) — une miniature 512x512 à qualité 70 tient
  /// largement sous la limite de diffusion réseau (`ProfileKernel.
  /// _maxPhotoBase64Chars`), contrairement à une photo brute de
  /// smartphone qui peut faire plusieurs Mo.
  Future<void> pickAndSetPhoto(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 70,
    );
    if (picked == null) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      // Nom de fichier FIXE (pas d'horodatage) : une nouvelle photo
      // remplace toujours l'ancienne au même endroit, pas d'accumulation
      // de vieux fichiers orphelins sur le disque au fil des changements.
      final destPath = "${docsDir.path}/profile_photo.jpg";
      final bytes = await picked.readAsBytes();
      await File(destPath).writeAsBytes(bytes, flush: true);

      final profile = repo.getOrCreateMine();
      profile.photoPath = destPath;
      repo.saveMine(profile);
      _mine = profile;
      notifyListeners();

      await node?.broadcastMyProfile();
    } catch (e) {
      Logger.error("Impossible d'enregistrer la photo de profil : $e");
      rethrow;
    }
  }

  Future<void> removePhoto() async {
    final profile = repo.getOrCreateMine();
    if (profile.photoPath.isNotEmpty) {
      try {
        final f = File(profile.photoPath);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Pas bloquant : au pire un fichier orphelin reste sur le disque.
      }
    }
    profile.photoPath = "";
    repo.saveMine(profile);
    _mine = profile;
    notifyListeners();
    await node?.broadcastMyProfile();
  }

  Future<void> saveNameAndBio({required String name, required String bio}) async {
    _saving = true;
    notifyListeners();
    try {
      final profile = repo.getOrCreateMine();
      profile.displayName = name.trim();
      profile.bio = bio.trim();
      repo.saveMine(profile);
      _mine = profile;
      await node?.broadcastMyProfile();
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  PeerProfileEntity? peerProfile(String peerId) => repo.getPeerProfile(peerId);
}
