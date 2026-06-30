import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'wallet_provider.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("Wallet")),
      body: ListView.builder(
        itemCount: provider.wallets.length,
        itemBuilder: (context, index) {
          final w = provider.wallets[index];

          return ListTile(
            title: Text(w.address),
            subtitle: Text("Balance: ${w.balance}"),
            trailing: const Icon(Icons.account_balance_wallet),
          );
        },
      ),
    );
  }
}