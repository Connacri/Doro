import 'package:flutter/material.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final toCtrl = TextEditingController();
  final amountCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Send")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: toCtrl,
              decoration: const InputDecoration(labelText: "To"),
            ),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // branch réseau (wallet core + DAG integration)
              },
              child: const Text("Send"),
            )
          ],
        ),
      ),
    );
  }
}