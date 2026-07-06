import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'profile_provider.dart';
import '../network/my_id_card.dart';

/// Vue du profil PUBLIC d'un pair distant — nom/bio/photo qu'IL a choisi
/// de diffuser (déclaratif, pas vérifié) + son adresse/QR, qui elle est
/// vérifiable (dérivée cryptographiquement de sa clé publique).
class PeerProfileScreen extends StatelessWidget {
  final String peerId;
  const PeerProfileScreen({super.key, required this.peerId});

  @override
  Widget build(BuildContext context) {
    // `watch` : se rafraîchit automatiquement si ce pair diffuse une
    // mise à jour de profil pendant que cet écran est ouvert.
    context.watch<ProfileProvider>();
    final peer = context.read<ProfileProvider>().peerProfile(peerId);

    final hasPhoto = peer != null && peer.photoBase64.isNotEmpty;
    Uint8List? photoBytes;
    if (hasPhoto) {
      try {
        photoBytes = base64Decode(peer.photoBase64);
      } catch (_) {
        photoBytes = null;
      }
    }

    final displayName = (peer?.displayName.isNotEmpty ?? false) ? peer!.displayName : null;

    return Scaffold(
      appBar: AppBar(title: Text(displayName ?? "Profil du pair")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 56,
                backgroundImage: photoBytes != null ? MemoryImage(photoBytes) : null,
                child: photoBytes == null ? const Icon(Icons.person, size: 56) : null,
              ),
            ),
            const SizedBox(height: 16),
            if (displayName != null)
              Center(
                child: Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            if (peer != null && peer.bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(peer.bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              ),
            ],
            if (peer == null) ...[
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "Ce pair n'a pas encore diffusé de profil (nom/photo) — "
                  "seule son adresse est connue pour l'instant.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ],
            const SizedBox(height: 24),
            MyIdCard(myId: peerId, title: "Adresse de ce pair"),
          ],
        ),
      ),
    );
  }
}
