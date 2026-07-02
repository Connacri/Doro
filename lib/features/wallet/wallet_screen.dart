import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'wallet_provider.dart';
import 'send_screen.dart';
import '../../core/wallet/genesis.dart';

/// Formate un solde stocké en unité atomique (18 décimales) en un montant
/// lisible, ex. 21000000 * 10^18 -> "21 000 000.000000 NOVA".
String formatNova(BigInt atomicBalance) {
  const decimals = 18;
  final divisor = BigInt.from(10).pow(decimals);
  final whole = atomicBalance ~/ divisor;
  final fraction = (atomicBalance % divisor).toString().padLeft(decimals, '0').substring(0, 6);

  final wholeStr = whole.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ' ',
      );

  return "$wholeStr.$fraction NOVA";
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  Future<void> _createWallet(BuildContext context) async {
    final provider = context.read<WalletProvider>();
    final wallet = await provider.createWallet();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Wallet créé : ${wallet.address}")),
    );
  }

  Future<void> _importWallet(BuildContext context) async {
    final controller = TextEditingController();
    final seed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Importer un wallet"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Colle la clé privée (seed hex, 64 caractères).\n"
              "Ne partage jamais cette valeur avec qui que ce soit.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: "Clé privée (seed hex)",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text("Importer"),
          ),
        ],
      ),
    );

    if (seed == null || seed.trim().isEmpty) return;
    if (!context.mounted) return;

    final provider = context.read<WalletProvider>();
    try {
      final wallet = await provider.importWallet(seed);
      if (!context.mounted) return;
      final isGenesis = Genesis.isGenesisAddress(wallet.address);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isGenesis
                ? "Wallet fondateur restauré — solde ${formatNova(wallet.balance)}"
                : "Wallet importé : ${wallet.address}",
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Import impossible : $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Wallet"),
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: "Importer un wallet",
            onPressed: () => _importWallet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createWallet(context),
        icon: const Icon(Icons.add),
        label: const Text("Créer un wallet"),
      ),
      body: ListView(
        children: [
          if (provider.wallets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  "Aucun wallet pour l'instant.\n"
                  "Crée un wallet (solde 0) ou importe une clé privée existante.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ...provider.wallets.map((w) {
            final isGenesis = Genesis.isGenesisAddress(w.address);
            return ListTile(
              leading: Icon(
                isGenesis ? Icons.stars : Icons.account_balance_wallet,
                color: isGenesis ? Colors.amber : null,
              ),
              title: Text(
                w.address,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                formatNova(w.balance),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isGenesis ? Colors.amber[800] : null,
                ),
              ),
              trailing: isGenesis
                  ? const Chip(label: Text("Fondateur"), visualDensity: VisualDensity.compact)
                  : null,
            );
          }),
          const Divider(),
          const SendScreen(),
        ],
      ),
    );
  }
}