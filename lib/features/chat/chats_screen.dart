// lib/features/chat/chats_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'chat_screen.dart';
import 'amis_screen.dart';

/// Écran d'accueil de la messagerie : toutes les discussions (amis +
/// pairs avec qui j'ai déjà échangé), triées par message le plus
/// récent — comme l'onglet principal de WhatsApp/Telegram.
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  String _formatTime(String? iso){
    if (iso == null) return "";
    final dt = DateTime.tryParse(iso);
    if (dt == null) return "";
    final now = DateTime.now();
    final sameDay = dt.year==now.year && dt.month==now.month && dt.day==now.day;
    if (sameDay) return "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
    return "${dt.day}/${dt.month}";
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final conversations = provider.conversations;
    final pendingCount = provider.receivedRequests.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Discussions"),
        actions: [
          IconButton(
            icon: Badge(isLabelVisible: pendingCount > 0, label: Text("$pendingCount"), child: const Icon(Icons.person_add_alt)),
            tooltip: "Contacts",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmisScreen())),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text("Aucune discussion pour l'instant.", textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text("Ajouter un ami"),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmisScreen())),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final c = conversations[i];
                return ListTile(
                  leading: Stack(children: [
                    CircleAvatar(radius: 22, child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : "?")),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        width: 11, height: 11,
                        decoration: BoxDecoration(
                          color: c.online ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                        ),
                      ),
                    ),
                  ]),
                  title: Row(children: [
                    Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.bold : FontWeight.normal))),
                    if (!c.isFriend) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.person_outline, size: 14, color: Colors.grey)),
                  ]),
                  subtitle: Text(
                    c.lastMessage ?? "Aucun message",
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.unread > 0 ? null : Colors.grey, fontWeight: c.unread > 0 ? FontWeight.w600 : FontWeight.normal),
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                      Text(_formatTime(c.lastTime), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (c.unread > 0) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: CircleAvatar(radius: 9, backgroundColor: Theme.of(context).colorScheme.primary, child: Text("${c.unread}", style: const TextStyle(fontSize: 10, color: Colors.white))),
                      ),
                    ]),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (v) {
                        if (v == "delete") {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Supprimer la discussion ?"),
                              content: Text("Tout l'historique avec ${c.name} sera effacé."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    context.read<ChatProvider>().clearHistory(c.peerId);
                                  },
                                  child: const Text("Supprimer"),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: "delete", child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.redAccent), SizedBox(width: 8), Text("Supprimer")])),
                      ],
                    ),
                  ]),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: c.peerId, peerName: c.name))),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.person_add),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmisScreen())),
      ),
    );
  }
}
