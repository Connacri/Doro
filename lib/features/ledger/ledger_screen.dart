import 'package:flutter/material.dart';
import '../../shared/widgets/tx_tile.dart';

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ledger")),
      body: ListView(
        children: const [
          TxTile(from: "A", to: "B", amount: "10"),
          TxTile(from: "C", to: "D", amount: "25"),
        ],
      ),
    );
  }
}