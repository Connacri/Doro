import 'package:flutter/material.dart';
import '../theme/colors.dart';

class TxTile extends StatelessWidget {
  final String from;
  final String to;
  final String amount;

  const TxTile({
    super.key,
    required this.from,
    required this.to,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.swap_horiz, color: AppColors.primary),
      title: Text("$from → $to"),
      subtitle: Text("Amount: $amount"),
    );
  }
}