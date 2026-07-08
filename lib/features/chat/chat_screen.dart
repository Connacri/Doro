// lib/features/chat/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/extensions/string_ext.dart';
import 'chat_provider.dart';
import '../profile/peer_profile_screen.dart';

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
  late ChatProvider _chatProvider;
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _chatProvider.addListener(_onProviderChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chatProvider.setActivePeer(widget.peerId);
    });
  }

  /// Affiche `lastSignalingError` (ex: tentative de reconnexion échouée
  /// vers ce pair) au lieu de le laisser invisible — voir le correctif
  /// dans `ChatProvider.send()`.
  void _onProviderChange() {
    final error = _chatProvider.lastSignalingError;
    if (error != null && error != _lastShownError && mounted) {
      _lastShownError = error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade800, duration: const Duration(seconds: 5)),
      );
      _chatProvider.clearSignalingError();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scrollCtrl.dispose();
    _chatProvider.removeListener(_onProviderChange);
    _chatProvider.setActivePeer(null);
    super.dispose();
  }

  void _send() {
    final text = controller.text;
    if (text.trim().isEmpty) return;
    final wasOffline = !_chatProvider.isOnline(widget.peerId);
    try {
      _chatProvider.send(widget.peerId, text);
      controller.clear();
      if (wasOffline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Pair hors ligne — message en attente, tentative de reconnexion en cours…"), duration: Duration(seconds: 3)),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollCtrl.hasClients) {
          scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    } catch (e) {
      // Ce catch ne devrait plus jamais rester muet : toute erreur réelle
      // ici est désormais visible pour l'utilisateur au lieu d'être
      // avalée en silence.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Échec de l'envoi : $e"), backgroundColor: Colors.red.shade800),
        );
      }
    }
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
              final navigator = Navigator.of(ctx);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final parsed = amountStr.toLocaleDouble();
              if (parsed == null || parsed <= 0) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text("Montant invalide")),
                );
                return;
              }
              final amount = BigInt.from(parsed * 1e18);
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

  Widget _buildStatusIcon(String? status) {
    if (status == 'read') {
      return const Icon(Icons.done_all, size: 14, color: Colors.cyanAccent);
    } else if (status == 'delivered') {
      return const Icon(Icons.done_all, size: 14, color: Colors.white60);
    } else if (status == 'sent') {
      return const Icon(Icons.check, size: 14, color: Colors.white60);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final messages = provider.messagesWith(widget.peerId);
    final online = provider.isOnline(widget.peerId);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PeerProfileScreen(peerId: widget.peerId)),
          ),
          child: Text(widget.peerName),
        ),
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(msg["text"] ?? "",
                                      style: TextStyle(
                                          fontWeight: isTx ? FontWeight.bold : FontWeight.normal,
                                          fontStyle: isTx ? FontStyle.italic : FontStyle.normal)),
                                ),
                                if (isMine && !isTx) ...[
                                  const SizedBox(width: 6),
                                  _buildStatusIcon(msg["status"]),
                                ],
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
                      decoration: const InputDecoration(hintText: "Écris un message...", border: OutlineInputBorder()),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}