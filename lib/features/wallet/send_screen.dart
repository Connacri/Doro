import 'package:flutter/material.dart';

class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final to = TextEditingController();
    final amount = TextEditingController();

    return Column(
      children: [
        TextField(controller: to),
        TextField(controller: amount),
        ElevatedButton(
          onPressed: () {
            // 🔥 FULL FLOW HOOK
            // Wallet → DAG → Consensus → P2P broadcast
          },
          child: const Text("Send"),
        )
      ],
    );
  }
}