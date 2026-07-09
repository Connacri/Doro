// lib/features/chat/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/extensions/string_ext.dart';
import 'chat_provider.dart';
import 'widgets/chat_animations.dart';
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
  Timer? _typingStopTimer;
  bool _isTypingNow = false;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chatProvider.setActivePeer(widget.peerId);
    });
    controller.addListener(_onTextChanged);
  }

  /// Diffuse "en train d'écrire" (throttlé) — comme WhatsApp/Messenger/
  /// Telegram : un signal tant que l'utilisateur tape, puis un dernier
  /// signal "stop" 2s après la dernière frappe.
  void _onTextChanged() {
    final hasText = controller.text.trim().isNotEmpty;
    if (hasText && !_isTypingNow) {
      _isTypingNow = true;
      _chatProvider.sendTyping(widget.peerId, true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      if (_isTypingNow) {
        _isTypingNow = false;
        _chatProvider.sendTyping(widget.peerId, false);
      }
    });
  }

  @override
  void dispose() {
    controller.removeListener(_onTextChanged);
    _typingStopTimer?.cancel();
    if (_isTypingNow) _chatProvider.sendTyping(widget.peerId, false);
    controller.dispose();
    scrollCtrl.dispose();
    _chatProvider.setActivePeer(null);
    super.dispose();
  }

  void _send() {
    final text = controller.text;
    if (text.trim().isEmpty) return;
    _chatProvider.send(widget.peerId, text);
    controller.clear();
    _typingStopTimer?.cancel();
    if (_isTypingNow) {
      _isTypingNow = false;
      _chatProvider.sendTyping(widget.peerId, false);
    }
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

  /// Menu contextuel façon WhatsApp/Telegram sur appui long : "Annuler
  /// l'envoi" (unsend, seulement sur mes propres messages, fenêtre de
  /// 2h côté serveur).
  void _showMessageMenu(BuildContext context, Map<String, dynamic> msg, bool isMine) {
    if (!isMine || msg["status"] == "deleted") return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.undo, color: Colors.redAccent),
            title: const Text("Annuler l'envoi (pour tout le monde)"),
            onTap: () async {
              Navigator.pop(ctx);
              final time = msg["time"] as String?;
              if (time == null) return;
              final ok = await context.read<ChatProvider>().unsend(widget.peerId, time);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Impossible d'annuler cet envoi (trop ancien ?)")),
                );
              }
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final messages = provider.messagesWith(widget.peerId);
    final online = provider.isOnline(widget.peerId);
    final typing = provider.isTyping(widget.peerId);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PeerProfileScreen(peerId: widget.peerId)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.peerName),
              const SizedBox(width: 8),
              if (typing)
                const Padding(padding: EdgeInsets.only(top: 2), child: TypingIndicator())
              else
                OnlineDot(online: online),
            ],
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.currency_bitcoin), tooltip: "Envoyer Crypto", onPressed: () => _sendCrypto(context)),
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
                        final isDeleted = msg["status"] == "deleted";

                        Widget bubble;
                        if (isDeleted) {
                          bubble = const DeletedMessageBubble();
                        } else {
                          bubble = Container(
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
                                  MessageStatusTicks(status: msg["status"] as String? ?? 'sent'),
                                ],
                              ],
                            ),
                          );
                        }

                        return Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () => _showMessageMenu(context, msg, isMine),
                            child: AnimatedMessageBubble(isMine: isMine, child: bubble),
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
