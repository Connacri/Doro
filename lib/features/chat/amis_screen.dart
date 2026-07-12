// lib/features/chat/amis_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'chat_screen.dart';
import '../network/qr_scan_screen.dart';
import '../network/my_id_card.dart';
import '../profile/profile_provider.dart';
import '../profile/peer_profile_screen.dart';
import '../../shared/widgets/supabase_unavailable_view.dart';
import '../../shared/theme/colors.dart';
import '../../core/storage/entities/contact_entity.dart';

/// Centre de gestion des contacts, façon grandes messageries :
/// - Rangée d'amis en ligne (façon "stories")
/// - Recherche
/// - Demandes reçues (accepter/refuser) / envoyées (annuler)
/// - Mes amis (discuter/supprimer)
/// Ajout via QR code (scanner l'ID d'un pair) ou clé publique collée.
class AmisScreen extends StatefulWidget {
  const AmisScreen({super.key});

  @override
  State<AmisScreen> createState() => _AmisScreenState();
}

class _AmisScreenState extends State<AmisScreen> {
  final _searchCtrl = TextEditingController();
  String _query = "";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFriend(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text("Ajouter un ami", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          ListTile(
            leading: const _SheetIcon(icon: Icons.qr_code_scanner),
            title: const Text("Scanner un QR code"),
            onTap: () => Navigator.pop(ctx, "qr"),
          ),
          ListTile(
            leading: const _SheetIcon(icon: Icons.key),
            title: const Text("Coller une clé publique"),
            onTap: () => Navigator.pop(ctx, "paste"),
          ),
          ListTile(
            leading: const _SheetIcon(icon: Icons.badge_outlined),
            title: const Text("Afficher mon QR / mon ID"),
            onTap: () => Navigator.pop(ctx, "myid"),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!context.mounted || result == null) return;

    if (result == "myid") {
      final myId = chat.myId;
      if (myId == null) return;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MyIdCard(myId: myId),
            ),
          ),
        ),
      );
      return;
    }

    if (result == "qr") {
      final scanned = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
      if (scanned != null && scanned.trim().isNotEmpty) {
        try {
          await chat.sendFriendRequest(scanned.trim());
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.red.shade800,
            ));
          }
          return;
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Demande d'ami envoyée")));
        }
      }
      return;
    }

    if (result == "paste" && context.mounted) {
      final controller = TextEditingController();
      final nameController = TextEditingController();
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Ajouter par clé publique"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nom (optionnel)")),
              const SizedBox(height: 8),
              TextField(controller: controller, decoration: const InputDecoration(labelText: "Clé publique", hintText: "0x...")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
            FilledButton(
              onPressed: () async {
                final key = controller.text.trim();
                Navigator.pop(ctx);
                if (key.isNotEmpty) {
                  try {
                    await chat.sendFriendRequest(key, name: nameController.text.trim().isEmpty ? null : nameController.text.trim());
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red.shade800,
                      ));
                    }
                    return;
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Demande d'ami envoyée")));
                  }
                }
              },
              child: const Text("Envoyer la demande"),
            ),
          ],
        ),
      );
    }
  }

  void _confirmRemove(BuildContext context, String publicKey, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer cet ami ?"),
        content: Text("$name sera retiré de ta liste d'amis. Ça ne l'avertit pas et n'empêche pas de futurs messages."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<ChatProvider>().removeFriend(publicKey);
              Navigator.pop(ctx);
            },
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    if (!provider.available) {
      return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(backgroundColor: AppColors.background, title: const Text("Contacts")), body: const SupabaseUnavailableView());
    }
    final received = provider.receivedRequests;
    final sent = provider.sentRequests;
    final allFriends = provider.friends;
    final friends = _query.isEmpty
        ? allFriends
        : allFriends.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();
    final onlineFriends = allFriends.where((c) => provider.isOnline(c.publicKey)).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      const Text("Contacts", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                      const Spacer(),
                      _RoundIconButton(icon: Icons.person_add_alt_1_rounded, onTap: () => _addFriend(context)),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Rechercher un ami",
                        hintStyle: TextStyle(color: Colors.white38),
                        prefixIcon: Icon(Icons.search, color: Colors.white38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
              if (onlineFriends.isNotEmpty && _query.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 92,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: onlineFriends.length,
                      itemBuilder: (context, i) {
                        final c = onlineFriends[i];
                        final avatarUrl = context.watch<ProfileProvider>().peerAvatarUrl(c.publicKey);
                        return _OnlineStory(
                          name: c.name,
                          avatarUrl: avatarUrl,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PeerProfileScreen(peerId: c.publicKey))),
                        );
                      },
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: TabBar(
                    indicator: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text("Demandes"),
                          if (received.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            CircleAvatar(radius: 8, backgroundColor: AppColors.error, child: Text("${received.length}", style: const TextStyle(fontSize: 9, color: Colors.white))),
                          ],
                        ]),
                      ),
                      Tab(text: "Mes amis (${allFriends.length})"),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(children: [
              // ---------------- Demandes ----------------
              ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (received.isEmpty && sent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: Column(children: [
                          Icon(Icons.mark_email_unread_outlined, size: 40, color: Colors.white24),
                          SizedBox(height: 12),
                          Text("Aucune demande en attente.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                        ]),
                      ),
                    ),
                  if (received.isNotEmpty) ...[
                    const _SectionLabel("Reçues"),
                    ...received.map((r) => _RequestTile(
                          name: r.name ?? _short(r.publicKey),
                          publicKey: r.publicKey,
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            _CircleGhostButton(icon: Icons.check, color: AppColors.success, onTap: () => context.read<ChatProvider>().acceptRequest(r.publicKey)),
                            const SizedBox(width: 8),
                            _CircleGhostButton(icon: Icons.close, color: AppColors.error, onTap: () => context.read<ChatProvider>().declineRequest(r.publicKey)),
                          ]),
                        )),
                  ],
                  if (sent.isNotEmpty) ...[
                    const _SectionLabel("Envoyées"),
                    ...sent.map((r) => _RequestTile(
                          name: r.name ?? _short(r.publicKey),
                          publicKey: r.publicKey,
                          subtitle: "En attente de réponse…",
                          trailing: TextButton(
                            onPressed: () => context.read<ChatProvider>().cancelRequest(r.publicKey),
                            child: const Text("Annuler", style: TextStyle(color: Colors.white54)),
                          ),
                        )),
                  ],
                ],
              ),

              // ---------------- Mes amis ----------------
              friends.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_outline, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            Text(
                              allFriends.isEmpty
                                  ? "Aucun ami pour l'instant.\nAjoute quelqu'un via QR code ou clé publique."
                                  : "Aucun résultat pour « $_query ».",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: friends.length,
                      itemBuilder: (context, i) {
                        final c = friends[i];
                        final online = provider.isOnline(c.publicKey);
                        final avatarUrl = context.watch<ProfileProvider>().peerAvatarUrl(c.publicKey);
                        return _FriendTile(
                          contact: c,
                          online: online,
                          avatarUrl: avatarUrl,
                          onOpenProfile: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PeerProfileScreen(peerId: c.publicKey))),
                          onOpenChat: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: c.publicKey, peerName: c.name))),
                          onRemove: () => _confirmRemove(context, c.publicKey, c.name),
                        );
                      },
                    ),
            ]),
          ),
        ),
      ),
    );
  }

  String _short(String key) => key.length > 14 ? "${key.substring(0, 8)}…${key.substring(key.length - 4)}" : key;
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.white54, letterSpacing: 0.4)),
      );
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _SheetIcon extends StatelessWidget {
  final IconData icon;
  const _SheetIcon({required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppColors.primary, size: 20),
      );
}

class _CircleGhostButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CircleGhostButton({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

/// Avatar "story" pour un ami en ligne, rangée horizontale en haut de liste.
class _OnlineStory extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final VoidCallback onTap;
  const _OnlineStory({required this.name, required this.avatarUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF00D084), Color(0xFF00B3FF)]),
                  ),
                  child: CircleAvatar(
                    radius: 27,
                    backgroundColor: AppColors.background,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.surface,
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                      child: avatarUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : "?", style: const TextStyle(color: Colors.white70)) : null,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.success, border: Border.all(color: AppColors.background, width: 2.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 60,
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final String name;
  final String publicKey;
  final String? subtitle;
  final Widget trailing;
  const _RequestTile({required this.name, required this.publicKey, this.subtitle, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(radius: 22, backgroundColor: AppColors.primary.withValues(alpha: 0.15), child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?", style: const TextStyle(color: AppColors.primary))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14.5)),
                Text(subtitle ?? publicKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white38), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final ContactEntity contact;
  final bool online;
  final String? avatarUrl;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenChat;
  final VoidCallback onRemove;

  const _FriendTile({
    required this.contact,
    required this.online,
    required this.avatarUrl,
    required this.onOpenProfile,
    required this.onOpenChat,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: GestureDetector(
          onTap: onOpenProfile,
          child: Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                child: avatarUrl == null ? Text(contact.name.isNotEmpty ? contact.name[0].toUpperCase() : "?", style: const TextStyle(color: AppColors.primary)) : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: online ? AppColors.success : Colors.grey, border: Border.all(color: AppColors.surface, width: 2)),
                ),
              ),
            ],
          ),
        ),
        title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 15)),
        subtitle: Text(
          online ? "En ligne" : contact.publicKey,
          style: TextStyle(fontSize: 11.5, color: online ? AppColors.success : Colors.white38, fontFamily: online ? null : 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _CircleGhostButton(icon: Icons.chat_bubble_outline, color: AppColors.primary, onTap: onOpenChat),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20), onPressed: onRemove),
        ]),
        onTap: onOpenChat,
      ),
    );
  }
}
