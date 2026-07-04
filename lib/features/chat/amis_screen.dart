// lib/features/chat/amis_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';
import 'chat_screen.dart';

class AmisScreen extends StatelessWidget {
  const AmisScreen({super.key});

  void _addContact(BuildContext context) {
    final controller = TextEditingController();
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ajouter un ami"),
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
            onPressed: () {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                context.read<ChatProvider>().addContact(
                      key,
                      name: nameController.text.trim().isEmpty ? null : nameController.text.trim(),
                    );
                Navigator.pop(ctx);
              }
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final contacts = provider.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Amis"),
        actions: [IconButton(icon: const Icon(Icons.person_add), onPressed: () => _addContact(context))],
      ),
      body: SafeArea(
        child: contacts.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.people_outline, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text("Aucun ami ajouté.\nAjoute une clé publique pour démarrer une conversation.", textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, i) {
                  final c = contacts[i];
                  final online = provider.isOnline(c.publicKey);
                  return ListTile(
                    leading: CircleAvatar(child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : "?")),
                    title: Text(c.name),
                    subtitle: Text(c.publicKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis),
                    trailing: Icon(Icons.circle, size: 10, color: online ? Colors.green : Colors.grey),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerId: c.publicKey, peerName: c.name))),
                  );
                },
              ),
      ),
    );
  }
}