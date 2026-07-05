import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/dag/transaction_model.dart';
import '../../shared/widgets/tx_tile.dart';
import 'ledger_provider.dart';

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LedgerProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("Ledger")),
      body: provider.transactions.isEmpty
          ? const Center(child: Text("No transactions yet"))
          : ListView.builder(
              itemCount: provider.transactions.length,
              itemBuilder: (context, index) {
                final tx = provider.transactions[index];
                // Un `receive` a `from == to` par convention (bloc de la
                // chaîne du destinataire) — pour l'affichage, on retrouve
                // le VRAI expéditeur d'origine via le `send` référencé,
                // sinon "0xABC… → 0xABC…" serait juste déroutant.
                String displayFrom = tx.from;
                if (tx.type == TxType.receive && tx.linkedSendId != null) {
                  final linkedSend = provider.dag.ledger[tx.linkedSendId];
                  if (linkedSend != null) displayFrom = linkedSend.from;
                }
                return TxTile(
                  from: displayFrom,
                  to: tx.to,
                  amount: tx.amount.toString(),
                  isFinal: provider.isFinal(tx.id),
                  confirmations: provider.confirmationsOf(tx.id),
                );
              },
            ),
    );
  }
}