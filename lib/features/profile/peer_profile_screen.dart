// lib/features/profile/peer_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'profile_provider.dart';
import '../chat/chat_provider.dart';
import '../chat/chat_screen.dart';
import '../../shared/theme/colors.dart';

/// Vue du profil PUBLIC d'un pair distant — nom/bio/photos qu'IL a
/// choisi de diffuser (déclaratif, pas vérifié) + son adresse/QR, qui
/// elle est vérifiable (dérivée cryptographiquement de sa clé publique).
class PeerProfileScreen extends StatefulWidget {
  final String peerId;
  const PeerProfileScreen({super.key, required this.peerId});

  @override
  State<PeerProfileScreen> createState() => _PeerProfileScreenState();
}

class _PeerProfileScreenState extends State<PeerProfileScreen> {
  bool _showQr = false;

  void _copyId(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.peerId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("ID copié dans le presse-papiers")),
    );
  }

  @override
  Widget build(BuildContext context) {
    // `watch` : se rafraîchit automatiquement si ce pair met à jour son
    // profil pendant que cet écran est ouvert (Supabase Realtime).
    final provider = context.watch<ProfileProvider>();
    final peer = provider.peerProfile(widget.peerId);
    final avatarUrl = provider.peerAvatarUrl(widget.peerId);
    final chat = context.watch<ChatProvider>();

    final displayName = (peer?['display_name'] as String?)?.isNotEmpty == true ? peer!['display_name'] as String : null;
    final bio = peer?['bio'] as String?;

    final isFriend = chat.available && chat.friends.any((c) => c.publicKey == widget.peerId);
    final requestSent = chat.available && chat.sentRequests.any((r) => r.publicKey == widget.peerId);
    final requestReceived = chat.available && chat.receivedRequests.any((r) => r.publicKey == widget.peerId);
    final isOnline = chat.available && chat.isOnline(widget.peerId);
    final shortId = widget.peerId.length > 14 ? "${widget.peerId.substring(0, 8)}…${widget.peerId.substring(widget.peerId.length - 4)}" : widget.peerId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(_showQr ? Icons.badge_outlined : Icons.qr_code_2_rounded, color: Colors.white),
                          tooltip: _showQr ? "Voir le profil" : "Voir le QR code",
                          onPressed: () => setState(() => _showQr = !_showQr),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (!_showQr) ...[
                      // ---- Avatar + halo dégradé ----
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 132,
                            height: 132,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(colors: [Color(0xFFFF7AC6), Color(0xFF6C5CE7), Color(0xFF00D0FF)]),
                            ),
                          ),
                          Container(
                            width: 122,
                            height: 122,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
                          ),
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: AppColors.surface,
                            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl == null ? const Icon(Icons.person, size: 52, color: Colors.white54) : null,
                          ),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? AppColors.success : Colors.grey,
                                border: Border.all(color: AppColors.background, width: 3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(displayName ?? shortId,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: isOnline ? AppColors.success : Colors.grey),
                          const SizedBox(width: 6),
                          Text(isOnline ? "En ligne" : "Hors ligne",
                              style: TextStyle(fontSize: 13, color: isOnline ? AppColors.success : Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (bio != null && bio.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                Icon(Icons.info_outline, size: 15, color: AppColors.primary),
                                SizedBox(width: 6),
                                Text("À propos", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              ]),
                              const SizedBox(height: 8),
                              Text(bio, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.white70)),
                            ],
                          ),
                        )
                      else if (peer == null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.hourglass_empty, size: 16, color: Colors.white38),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Ce pair n'a pas encore de profil (nom/photo) — seule son adresse est connue pour l'instant.",
                                  style: TextStyle(fontSize: 12.5, color: Colors.white54),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 14),

                      // ---- Carte adresse (courte + copier) ----
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.fingerprint, color: AppColors.primary, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Adresse vérifiable", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
                                  Text(widget.peerId, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white54), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            IconButton(icon: const Icon(Icons.copy, size: 18, color: Colors.white54), onPressed: () => _copyId(context)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- Actions ----
                      Row(
                        children: [
                          if (isFriend) ...[
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                label: const Text("Discuter"),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ChatScreen(peerId: widget.peerId, peerName: displayName ?? shortId),
                                )),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                                  foregroundColor: Colors.redAccent,
                                ),
                                icon: const Icon(Icons.person_remove_outlined, size: 18),
                                label: const Text("Retirer"),
                                onPressed: () => _confirmRemoveFriend(context),
                              ),
                            ),
                          ] else if (requestReceived) ...[
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text("Accepter"),
                                onPressed: () => context.read<ChatProvider>().acceptRequest(widget.peerId),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  side: const BorderSide(color: Colors.white24),
                                ),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text("Refuser"),
                                onPressed: () => context.read<ChatProvider>().declineRequest(widget.peerId),
                              ),
                            ),
                          ] else if (requestSent) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  side: const BorderSide(color: Colors.white24),
                                ),
                                icon: const Icon(Icons.hourglass_top, size: 18),
                                label: const Text("Demande envoyée — annuler"),
                                onPressed: () => context.read<ChatProvider>().cancelRequest(widget.peerId),
                              ),
                            ),
                          ] else ...[
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.person_add_alt_1, size: 18),
                                label: const Text("Ajouter en ami"),
                                onPressed: !chat.available ? null : () async {
                                  try {
                                    await context.read<ChatProvider>().sendFriendRequest(widget.peerId, name: displayName);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Demande d'ami envoyée")));
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800));
                                    }
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ] else ...[
                      // ---- Vue QR code (style paramètres messagerie) ----
                      const SizedBox(height: 12),
                      Text(displayName ?? shortId,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            QrImageView(data: widget.peerId, version: QrVersions.auto, size: 220, backgroundColor: Colors.white),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12)),
                              child: const Icon(Icons.bolt, color: AppColors.primary, size: 22),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Ce QR code correspond à l'adresse cryptographique de ce pair — le scanner permet de l'ajouter en ami.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5, color: Colors.white54),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Expanded(child: Text(widget.peerId, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                            IconButton(icon: const Icon(Icons.copy, size: 16, color: Colors.white54), onPressed: () => _copyId(context)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveFriend(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Retirer ce pair de tes amis ?"),
        content: const Text("Il ne sera plus dans ta liste d'amis. Ça ne l'avertit pas et n'empêche pas de futurs messages."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<ChatProvider>().removeFriend(widget.peerId);
              Navigator.pop(ctx);
            },
            child: const Text("Retirer"),
          ),
        ],
      ),
    );
  }
}
