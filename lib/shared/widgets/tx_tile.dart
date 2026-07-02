import 'package:flutter/material.dart';
import '../theme/colors.dart';

class TxTile extends StatelessWidget {
  final String from;
  final String to;
  final String amount;
  final bool isFinal;
  final int confirmations;

  const TxTile({
    super.key,
    required this.from,
    required this.to,
    required this.amount,
    this.isFinal = false,
    this.confirmations = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        isFinal ? Icons.verified : Icons.hourglass_top,
        color: isFinal ? Colors.green : Colors.orange,
      ),
      title: Text(
        "${_short(from)} → ${_short(to)}",
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      subtitle: Text("Montant : $amount"),
      trailing: Chip(
        label: Text(
          isFinal ? "Confirmée ($confirmations)" : "En attente",
          style: const TextStyle(fontSize: 11),
        ),
        backgroundColor: (isFinal ? Colors.green : Colors.orange).withValues(alpha: 0.15),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  String _short(String address) =>
      address.length > 14 ? "${address.substring(0, 8)}…${address.substring(address.length - 4)}" : address;
}