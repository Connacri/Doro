// lib/features/chat/amis_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'chat_screen.dart';
import '../network/qr_scan_screen.dart';
import '../network/my_id_card.dart';

/// Centre de gestion des contacts, façon grandes messageries :
/// - Demandes reçues (accepter/refuser)
/// - Demandes envoyées (annuler)
/// - Mes amis (discuter/supprimer)
/// Ajout via QR code (scanner l'ID d'un pair) ou clé publique collée.
class AmisScreen extends StatelessWidget {
  const AmisScreen({super.key});

  Future<void> _addFriend(BuildContext context) async {
    final chat = context.read<ChatProvider>();
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text("Scanner un QR code"),
            onTap: () => Navigator.pop(ctx, "qr"),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text("Coller une clé publique"),
            onTap: () => Navigator.pop(ctx, "paste"),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text("Afficher mon QR / mon ID"),
            onTap: () => Navigator.pop(ctx, "myid"),
          ),
        ]),
      ),
    );
    if (!context.mounted || result == null) return;

    if (result == "myid") {
      showDialog(context: context, builder: (_) => Dialog(child: Padding(padding: const EdgeInsets.all(16), child: MyIdCard(myId: chat.myId))));
      return;
    }

    if (result == "qr") {
      final scanned = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
      if (scanned != null && scanned.trim().isNotEmpty) {
        await chat.sendFriendRequest(scanned.trim());
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
                  await chat.sendFriendRequest(key, name: nameController.text.trim().isEmpty ? null : nameController.text.trim());
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
    final received = provider.receivedRequests;
    final sent = provider.sentRequests;
    final friends = provider.friends;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Contacts"),
          actions: [IconButton(icon: const Icon(Icons.person_add), onPressed: () => _addFriend(context))],
          bottom: TabBar(tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text("Demandes"),
                if (received.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  CircleAvatar(radius: 9, backgroundColor: Colors.red, child: Text("${received.length}", style: const TextStyle(fontSize: 10, color: Colors.white))),
                ],
              ]),
            ),
            Tab(text: "Mes amis (${friends.length})"),
          ]),
        ),
        body: TabBarView(children: [
          // ---------------- Demandes ----------------
          ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (received.isEmpty && sent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text("Aucune demande en attente.", textAlign: TextAlign.center)),
                ),
              if (received.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text("Reçues", style: TextStyle(fontWeight: FontWeight.bold))),
                ...received.map((r) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(r.name ?? _short(r.publicKey)),
                      subtitle: Text(r.publicKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => context.read<ChatProvider>().acceptRequest(r.publicKey)),
                        IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => context.read<ChatProvider>().declineRequest(r.publicKey)),
                      ]),
                    )),
              ],
              if (sent.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text("Envoyées", style: TextStyle(fontWeight: FontWeight.bold))),
                ...sent.map((r) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.hourglass_top)),
                      title: Text(r.name ?? _short(r.publicKey)),
                      subtitle: const Text("En attente de réponse…"),
                      trailing: TextButton(onPressed: () => context.read<ChatProvider>().cancelRequest(r.publicKey), child: const Text("Annuler")),
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
                      children: const [
                        Icon(Icons.people_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text("Aucun ami pour l'instant.\nAjoute quelqu'un via QR code ou clé publique.", textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, i) {
                    final c = friends[i];
                    final online = provider.isOnline(c.publicKey);
                    return ListTile(
                      leading: CircleAvatar(child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : "?")),
                      title: Text(c.name),
                      subtitle: Text(c.publicKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle, size: 10, color: online ? Colors.green : Colors.grey),
                        IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _confirmRemove(context, c.publicKey, c.name)),
                      ]),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: c.publicKey, peerName: c.name))),
                    );
                  },
                ),
        ]),
      ),
    );
  }

  String _short(String key) => key.length > 14 ? "${key.substring(0, 8)}…${key.substring(key.length - 4)}" : key;
}
