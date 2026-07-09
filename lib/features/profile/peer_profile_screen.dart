// lib/features/profile/peer_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'profile_provider.dart';
import '../network/my_id_card.dart';

/// Vue du profil PUBLIC d'un pair distant — nom/bio/photos qu'IL a
/// choisi de diffuser (déclaratif, pas vérifié) + son adresse/QR, qui
/// elle est vérifiable (dérivée cryptographiquement de sa clé publique).
class PeerProfileScreen extends StatelessWidget {
  final String peerId;
  const PeerProfileScreen({super.key, required this.peerId});

  @override
  Widget build(BuildContext context) {
    // `watch` : se rafraîchit automatiquement si ce pair met à jour son
    // profil pendant que cet écran est ouvert (Supabase Realtime).
    final provider = context.watch<ProfileProvider>();
    final peer = provider.peerProfile(peerId);
    final avatarUrl = provider.peerAvatarUrl(peerId);

    final displayName = (peer?['display_name'] as String?)?.isNotEmpty == true ? peer!['display_name'] as String : null;
    final bio = peer?['bio'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(displayName ?? "Profil du pair")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 56,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null ? const Icon(Icons.person, size: 56) : null,
              ),
            ),
            const SizedBox(height: 16),
            if (displayName != null)
              Center(
                child: Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            if (bio != null && bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(bio, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              ),
            ],
            if (peer == null) ...[
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "Ce pair n'a pas encore de profil (nom/photo) — "
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
