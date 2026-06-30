import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messages = <String>[];
  final controller = TextEditingController();

  void send() {
    final msg = controller.text;

    setState(() {
      messages.add(msg);
    });

    // 🔥 BROADCAST HOOK (P2P)
    // NetworkCore.instance.p2p.broadcast(...)
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: messages.map((e) => Text(e)).toList(),
          ),
        ),
        Row(
          children: [
            Expanded(child: TextField(controller: controller)),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: send,
            )
          ],
        )
      ],
    );
  }
}