// lib/features/chat/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_provider.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  const ChatScreen({super.key, required this.peerId, required this.peerName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final scrollCtrl = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    scrollCtrl.dispose();
    super.dispose();
  }

  void _send(BuildContext context) {
    final text = controller.text;
    if (text.trim().isEmpty) return;
    context.read<ChatProvider>().send(widget.peerId, text);
    controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollCtrl.hasClients) {
        scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendCrypto(BuildContext context) {
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Envoyer des DORO à ${widget.peerName}"),
        content: TextField(
          controller: amountController,
          decoration: const InputDecoration(labelText: "Montant"),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            onPressed: () async {
              final amountStr = amountController.text.trim();
              if (amountStr.isEmpty) return;
              final amount = BigInt.from(double.parse(amountStr) * 1e18);
              final navigator = Navigator.of(ctx);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final ok = await context.read<ChatProvider>().sendCrypto(widget.peerId, amount);
              navigator.pop();
              scaffoldMessenger.showSnackBar(SnackBar(content: Text(ok ? "Transfert réussi" : "Échec du transfert")));
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
    final messages = provider.messagesWith(widget.peerId);
    final online = provider.isOnline(widget.peerId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerName),
        actions: [
          IconButton(icon: const Icon(Icons.currency_bitcoin), tooltip: "Envoyer Crypto", onPressed: () => _sendCrypto(context)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Icon(Icons.circle, size: 10, color: online ? Colors.green : Colors.grey)),
          ),
        ],
      ),
      // top:false car l'AppBar gère déjà la status bar — évite un double
      // padding en haut ; bottom:true est ce qui protège des boutons de
      // navigation Android en bas.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text("Aucun message. Envoie le premier !"))
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMine = msg["from"] == provider.myId;
                        final isTx = msg["type"] == "tx_info";
                        return Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isTx
                                  ? Colors.amber.shade900.withValues(alpha: 0.5)
                                  : (isMine ? Colors.purple.shade800 : Colors.grey.shade800),
                              borderRadius: BorderRadius.circular(12),
                              border: isTx ? Border.all(color: Colors.amber) : null,
                            ),
                            child: Text(msg["text"] ?? "",
                                style: TextStyle(
                                    fontWeight: isTx ? FontWeight.bold : FontWeight.normal,
                                    fontStyle: isTx ? FontStyle.italic : FontStyle.normal)),
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
                      decoration: const InputDecoration(hintText: "Écris un message...", border: OutlineInputBorder()),
                      onSubmitted: (_) => _send(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(icon: const Icon(Icons.send), onPressed: () => _send(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}