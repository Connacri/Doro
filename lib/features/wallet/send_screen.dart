import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'wallet_provider.dart';
import 'wallet_screen.dart' show formatDoro;
import '../../core/wallet/token_config.dart';
import '../../core/wallet/wallet_model.dart';
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
  BigInt _remaining = BigInt.zero;
  String? _selectedAddress;
  BigInt _balance = BigInt.zero;

  @override
  void initState() {
    super.initState();
    amountCtrl.addListener(_updateRemaining);
  }

  @override
  void dispose() {
    amountCtrl.removeListener(_updateRemaining);
    toCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  Wallet? _selectedWallet(WalletProvider provider) {
    if (_selectedAddress == null || provider.wallets.isEmpty) return null;
    return provider.wallets.where((w) => w.address == _selectedAddress).firstOrNull;
  }

  void _updateRemaining() {
    final provider = context.read<WalletProvider>();
    final wallet = _selectedWallet(provider);
    final balance = wallet?.balance ?? BigInt.zero;
    final amountStr = amountCtrl.text.trim();
    final humanAmount = amountStr.toLocaleDouble();
    final amount = humanAmount != null && humanAmount > 0
        ? BigInt.from(humanAmount * 1e18)
        : BigInt.zero;
    setState(() {
      _balance = balance;
      _remaining = balance - amount;
    });
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
    final wallet = _selectedWallet(provider);
    if (wallet == null) return;

    setState(() => _sending = true);
    try {
      final txId = await provider.send(
        from: wallet.address,
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
    final provider = context.watch<WalletProvider>();
    final wallets = provider.wallets;
    if (_selectedAddress == null && wallets.isNotEmpty) {
      _selectedAddress = wallets.last.address;
    }
    final wallet = _selectedWallet(provider);
    final overspend = _remaining < BigInt.zero;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wallets.length > 1)
            DropdownButtonFormField<String>(
              initialValue: _selectedAddress,
              decoration: const InputDecoration(labelText: "Wallet source", border: OutlineInputBorder(), isDense: true),
              items: wallets.map((w) => DropdownMenuItem(
                value: w.address,
                child: Text("${w.address.substring(0, 10)}…${w.address.substring(w.address.length - 4)}  (${formatDoro(w.balance, compact: true)})",
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              )).toList(),
              onChanged: (v) => setState(() => _selectedAddress = v),
            ),
          if (wallets.length > 1) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Text("Solde : ", style: TextStyle(fontSize: 13)),
                Text(formatDoro(_balance), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          if (amountCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: overspend ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.green.shade900.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(overspend ? "Dépassement : " : "Restant : ", style: TextStyle(fontSize: 13, color: overspend ? Colors.redAccent : Colors.greenAccent)),
                  Text(formatDoro(overspend ? -_remaining : _remaining),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: overspend ? Colors.redAccent : Colors.greenAccent)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
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
            onPressed: _sending || overspend || wallet == null ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(overspend ? "Montant trop élevé" : "Envoyer"),
          ),
        ],
      ),
    );
  }
}