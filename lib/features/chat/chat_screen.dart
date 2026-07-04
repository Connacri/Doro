import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final contactController = TextEditingController();
  final amountController = TextEditingController();
  final addressController = TextEditingController();
  final scrollCtrl = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    contactController.dispose();
    amountController.dispose();
    addressController.dispose();
    scrollCtrl.dispose();
    super.dispose();
  }

  void send() {
    final text = controller.text;
    if (text.trim().isEmpty) return;
    context.read<ChatProvider>().send(text);
    controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtrl.hasClients) {
        scrollCtrl.animateTo(
          scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addContact() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ajouter un contact"),
        content: TextField(
          controller: contactController,
          decoration: const InputDecoration(
            labelText: "Clé publique",
            hintText: "0x...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () {
              if (contactController.text.isNotEmpty) {
                context.read<ChatProvider>().addContact(contactController.text);
                contactController.clear();
                Navigator.pop(ctx);
              }
            },
            child: const Text("Ajouter"),
          ),
        ],
      ),
    );
  }

  void _sendCrypto() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Envoyer des DORO"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: "Adresse du destinataire",
                hintText: "0x...",
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: "Montant",
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () async {
              final addr = addressController.text.trim();
              final amountStr = amountController.text.trim();
              if (addr.isNotEmpty && amountStr.isNotEmpty) {
                final amount = BigInt.from(double.parse(amountStr) * 1e18);
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final ok = await context.read<ChatProvider>().sendCrypto(addr, amount);
                if (mounted) {
                   navigator.pop();
                   scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text(ok ? "Transfert réussi" : "Échec du transfert")),
                  );
                }
              }
            },
            child: const Text("Envoyer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final peers = provider.onlinePeers;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat"),
        actions: [
          IconButton(
            icon: const Icon(Icons.currency_bitcoin),
            onPressed: _sendCrypto,
            tooltip: "Envoyer Crypto",
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _addContact,
          ),
          if (peers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text("Offline", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  Text("${peers.length} en ligne",
                      style: const TextStyle(fontSize: 12, color: Colors.green)),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (peers.isEmpty)
            Container(
              width: double.infinity,
              color: Colors.grey.shade900,
              padding: const EdgeInsets.all(8),
              child: const Text(
                "Aucun pair connecté. Ouvre l'onglet Network pour démarrer.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            )
          else
            Container(
              width: double.infinity,
              color: Colors.green.shade900.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                "🟢 Connecté à ${peers.length} pair${peers.length > 1 ? 's' : ''}",
                style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
              ),
            ),
          Expanded(
            child: provider.messages.isEmpty
                ? const Center(child: Text("Aucun message. Envoie le premier !"))
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(8),
                    itemCount: provider.messages.length,
                    itemBuilder: (context, index) {
                      final msg = provider.messages[index];
                      final isMine = msg["from"] == provider.myId;
                      final isTx = msg["type"] == "tx_info";

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isTx
                                ? Colors.amber.shade900.withValues(alpha: 0.5)
                                : (isMine ? Colors.purple.shade800 : Colors.grey.shade800),
                            borderRadius: BorderRadius.circular(12),
                            border: isTx ? Border.all(color: Colors.amber) : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isMine ? "Moi" : msg["from"].toString().substring(0, 12),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                              Text(
                                msg["text"] ?? "",
                                style: TextStyle(
                                  fontWeight: isTx ? FontWeight.bold : FontWeight.normal,
                                  fontStyle: isTx ? FontStyle.italic : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: "Écris un message...",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
