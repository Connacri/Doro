import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/p2p/p2p_node.dart';
import '../../core/storage/entities/peer_profile_entity.dart';
import '../../core/storage/entities/profile_entity.dart';
import '../../core/storage/repositories/profile_repository.dart';
import '../../core/utils/logger.dart';

class ProfileProvider extends ChangeNotifier {
  final ProfileRepository repo;
  final P2PNode? node;

  ProfileEntity? _mine;
  ProfileEntity? get mine => _mine;

  bool _saving = false;
  bool get saving => _saving;

  ProfileProvider(this.repo, {this.node}) {
    _mine = repo.getOrCreateMine();
    node?.profileChanges.listen((_) => notifyListeners());
  }

  String get myAddress => node?.nodeId ?? "";

  Future<void> pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    if (picked.path == null) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final destPath = "${docsDir.path}/profile_photo.jpg";
      final bytes = await File(picked.path!).readAsBytes();
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
