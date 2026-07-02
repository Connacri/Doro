import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'wallet_provider.dart';
import 'send_screen.dart';
import '../../core/wallet/genesis.dart';
import '../../core/wallet/token_config.dart';

/// Formate un solde stocké en unité atomique (18 décimales) en un montant
/// lisible.
String formatDoro(BigInt atomicBalance) {
  const decimals = 18;
  final divisor = BigInt.from(10).pow(decimals);
  final whole = atomicBalance ~/ divisor;
  final fraction = (atomicBalance % divisor).toString().padLeft(decimals, '0').substring(0, 6);

  final wholeStr = whole.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ' ',
      );

  return "$wholeStr.$fraction ${TokenConfig.symbol}";
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  Future<void> _createWallet(BuildContext context) async {
    final provider = context.read<WalletProvider>();
    final result = await provider.createWallet();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Wallet créé — Sauvegarde obligatoire"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Voici ta seed (clé privée). Elle est le SEUL moyen "
              "de récupérer tes fonds si tu perds l'accès à cet appareil.\n\n"
              "Note-la sur un papier et conserve-la dans un endroit sûr. "
              "Ne la partage JAMAIS avec personne.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                result.seedHex,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text("Copier la seed"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.seedHex));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text("Seed copiée dans le presse-papiers")),
              );
            },
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("J'ai sauvegardé ma seed"),
          ),
        ],
      ),
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
              "Colle ta seed (64 caractères hex) que tu as sauvegardée "
              "lors de la création du wallet.\n"
              "Ne partage jamais cette valeur.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: "Seed (64 caractères hex)",
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
                ? "Wallet fondateur restauré — solde ${formatDoro(wallet.balance)}"
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
                formatDoro(w.balance),
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