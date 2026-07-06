// lib/features/wallet/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'wallet_provider.dart';
import 'send_screen.dart';
import '../ledger/ledger_provider.dart';
import '../chat/chat_screen.dart';
import '../../core/wallet/genesis.dart';
import '../../core/wallet/token_config.dart';
import '../../core/dag/transaction_model.dart';

String formatDoro(BigInt atomicBalance, {bool compact = true}) {
  const decimals = 18;
  final divisor = BigInt.from(10).pow(decimals);
  final whole = atomicBalance ~/ divisor;
  final fraction = (atomicBalance % divisor).toString().padLeft(decimals, '0').substring(0, 6);

  if (compact && whole >= BigInt.from(1000000000)) {
    final b = whole.toDouble() / 1000000000;
    return "${b.toStringAsFixed(2)}B ${TokenConfig.symbol}";
  }
  if (compact && whole >= BigInt.from(1000000)) {
    final m = whole.toDouble() / 1000000;
    return "${m.toStringAsFixed(2)}M ${TokenConfig.symbol}";
  }

  final wholeStr = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
  return "$wholeStr.$fraction ${TokenConfig.symbol}";
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _backupPromptShown = false;

  Future<void> _showBackupDialog(BuildContext context, String seedHex, {required bool auto}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(auto ? "Ton wallet a été créé — Sauvegarde obligatoire" : "Wallet créé — Sauvegarde obligatoire"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Voici ta seed (clé privée). Elle est le SEUL moyen de récupérer tes fonds "
              "si tu perds l'accès à cet appareil.\n\nNote-la sur un papier et conserve-la "
              "dans un endroit sûr. Ne la partage JAMAIS avec personne.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(seedHex, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text("Copier la seed"),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: seedHex));
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Seed copiée")));
            },
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("J'ai sauvegardé ma seed")),
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
            const Text("Colle ta seed (64 caractères hex). Ne la partage jamais.",
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Seed (64 caractères hex)", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Annuler")),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text("Importer")),
        ],
      ),
    );
    if (seed == null || seed.trim().isEmpty || !context.mounted) return;
    final provider = context.read<WalletProvider>();
    try {
      final wallet = await provider.importWallet(seed);
      if (!context.mounted) return;
      final isGenesis = Genesis.isGenesisAddress(wallet.address);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isGenesis
            ? "Wallet fondateur restauré — solde ${formatDoro(wallet.balance)}"
            : "Wallet importé : ${wallet.address}"),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import impossible : $e")));
    }
  }

  Future<void> _openChatWith(BuildContext context, String peerId) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peerId: peerId, peerName: peerId.substring(0, 12))),
    );
  }

  /// Crée automatiquement un wallet dès le 1er lancement, SANS demander de
  /// choix bloquant à l'utilisateur — un wallet doit exister par défaut,
  /// exactement comme la plupart des wallets grand public (MetaMask, Trust
  /// Wallet...). L'import d'une seed existante (ex: le fondateur qui
  /// restaure son wallet de trésorerie) reste possible à tout moment via
  /// l'icône clé 🔑 de l'AppBar, avant ou après cet auto-create — importer
  /// une seed connue ne fait que révéler le solde réel de CETTE adresse-là
  /// (voir `WalletProvider.importWallet`), il ne détruit jamais le wallet
  /// auto-créé qui reste disponible en parallèle dans la liste.
  Future<void> _autoCreateFirstWallet(BuildContext context) async {
    final provider = context.read<WalletProvider>();
    final result = await provider.createWallet();
    if (!context.mounted) return;
    await _showBackupDialog(context, result.seedHex, auto: true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();
    final ledger = context.watch<LedgerProvider>();

    if (provider.isLoaded && provider.wallets.isEmpty && !_backupPromptShown) {
      _backupPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _autoCreateFirstWallet(context);
      });
    }

    if (provider.isLoaded && !_backupPromptShown && provider.pendingBackupSeed != null) {
      _backupPromptShown = true;
      final seed = provider.pendingBackupSeed!;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _showBackupDialog(context, seed, auto: true);
        if (context.mounted) context.read<WalletProvider>().clearPendingBackup();
      });
    }

    final myAddress = provider.wallets.isNotEmpty ? provider.wallets.first.address : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Wallet"),
        actions: [
          IconButton(icon: const Icon(Icons.key), tooltip: "Importer un wallet", onPressed: () => _importWallet(context)),
        ],
      ),
      // Pas de FAB : le premier wallet est créé automatiquement au
      // 1er lancement. L'import d'une seed existante se fait via 🔑.
      body: SafeArea(
        child: ListView(
          children: [
            if (provider.wallets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("Aucun wallet pour l'instant.", textAlign: TextAlign.center)),
              ),
            ...provider.wallets.map((w) {
              final isGenesis = Genesis.isGenesisAddress(w.address);
              return ListTile(
                leading: Icon(isGenesis ? Icons.stars : Icons.account_balance_wallet, color: isGenesis ? Colors.amber : null),
                title: Text(w.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 13), overflow: TextOverflow.ellipsis),
                subtitle: Text(formatDoro(w.balance), style: TextStyle(fontWeight: FontWeight.bold, color: isGenesis ? Colors.amber[800] : null)),
                trailing: isGenesis
                    ? const Chip(label: Text("Fondateur"), visualDensity: VisualDensity.compact)
                    : IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: "Supprimer le wallet",
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text("Réinitialiser l'app ?"),
                              content: const Text(
                                "Cela supprime TOUTES les données locales : wallet, "
                                "clé privée, historique des transactions. Assure-toi "
                                "d'avoir sauvegardé ta seed avant.",
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text("Annuler")),
                                FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: const Text("Tout supprimer")),
                              ],
                            ),
                          );
                          if (confirm == true && context.mounted) {
                            await context.read<WalletProvider>().resetAll();
                          }
                        },
                      ),
              );
            }),
            const Divider(),
            const SendScreen(),
            const Divider(),
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text("Transactions", style: TextStyle(fontWeight: FontWeight.bold))),
            if (ledger.transactions.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text("Aucune transaction pour l'instant.")),
            ...ledger.transactions.map((tx) {
              // Un `receive` a `from == to == moi` par convention (bloc
              // de MA chaîne qui réclame un paiement) — sans ce cas
              // particulier, `isSent` valait `true` pour CHAQUE paiement
              // REÇU (puisque `tx.from == myAddress`), affichant à tort
              // toute réception comme un envoi vers moi-même.
              final bool isSent;
              final String counterparty;
              if (tx.type == TxType.receive) {
                isSent = false;
                final linkedSend = ledger.dag.ledger[tx.linkedSendId];
                counterparty = linkedSend?.from ?? tx.from;
              } else {
                isSent = tx.from == myAddress;
                counterparty = isSent ? tx.to : tx.from;
              }
              return ListTile(
                leading: Icon(isSent ? Icons.arrow_upward : Icons.arrow_downward, color: isSent ? Colors.redAccent : Colors.greenAccent),
                title: Text(counterparty, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), overflow: TextOverflow.ellipsis),
                subtitle: Text("${formatDoro(tx.amount)} — ${ledger.isFinal(tx.id) ? 'confirmé' : '${ledger.confirmationsOf(tx.id)} confirmation(s)'}"),
                trailing: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  tooltip: "Discuter",
                  onPressed: () => _openChatWith(context, counterparty),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}