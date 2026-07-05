import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'wallet_provider.dart';
import '../../core/wallet/token_config.dart';
import '../../shared/extensions/string_ext.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final toCtrl = TextEditingController();
  final amountCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    toCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = toCtrl.text.trim();
    final amountStr = amountCtrl.text.trim();
    if (to.isEmpty || amountStr.isEmpty) return;

    final humanAmount = amountStr.toLocaleDouble();
    if (humanAmount == null || humanAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Montant invalide")),
      );
      return;
    }
    final amount = BigInt.from(humanAmount * 1e18);

    final provider = context.read<WalletProvider>();
    final wallets = provider.wallets;
    if (wallets.isEmpty) return;

    setState(() => _sending = true);
    try {
      final txId = await provider.send(
        from: wallets.first.address,
        to: to,
        amount: amount,
      );
      if (!mounted) return;
      if (txId != null) {
        toCtrl.clear();
        amountCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Transaction envoyée — en attente de confirmation par le réseau"),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Échec de l'envoi (solde insuffisant ou clé introuvable)"),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e")),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: toCtrl,
            decoration: const InputDecoration(
              labelText: "Adresse du destinataire",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            decoration: const InputDecoration(
              labelText: "Montant (${TokenConfig.symbol})",
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Envoyer"),
          ),
        ],
      ),
    );
  }
}