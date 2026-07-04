// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../wallet/wallet_provider.dart';
import '../wallet/wallet_screen.dart' show formatDoro;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _marketComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Le marché d'échange arrive dans la prochaine étape (protocole d'ordres P2P).")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final balance = wallet.wallets.isNotEmpty ? wallet.wallets.first.balance : BigInt.zero;

    return Scaffold(
      appBar: AppBar(title: const Text("Doro")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Solde total", style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    Text(formatDoro(balance), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.sell),
                    label: const Text("Vendre"),
                    onPressed: () => _marketComingSoon(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text("Acheter"),
                    onPressed: () => _marketComingSoon(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text("Offres sur le marché", style: TextStyle(fontWeight: FontWeight.bold)),
            const Padding(padding: EdgeInsets.all(16), child: Text("Aucune offre — marché pas encore en ligne.")),
          ],
        ),
      ),
    );
  }
}