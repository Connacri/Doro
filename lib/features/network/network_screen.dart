import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network_provider.dart';

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final net = Provider.of<NetworkProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("P2P Network")),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () => net.init("node-${DateTime.now().millisecondsSinceEpoch}"),
            child: const Text("Start Node"),
          ),
          ElevatedButton(
            onPressed: () {
              net.addPeer("peer1", "192.168.1.10");
            },
            child: const Text("Add Peer"),
          ),
        ],
      ),
    );
  }
}