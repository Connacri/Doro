import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bootstrap/bootstrap_service.dart';
import 'network_provider.dart';
import 'my_id_card.dart';
import 'qr_scan_screen.dart';
import '../chat/chat_screen.dart';

class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final _idController = TextEditingController();
  bool _connecting = false;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _addPeer(String peerId) async {
    final id = peerId.trim();
    if (id.isEmpty) return;

    setState(() => _connecting = true);
    try {
      await context.read<NetworkProvider>().connectPeer(id);
      if (!mounted) return;
      _idController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Demande de connexion envoyée à $id")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible d'ajouter ce pair : $e")),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (scanned != null && scanned.isNotEmpty) {
      await _addPeer(scanned);
    }
  }

  @override
  Widget build(BuildContext context) {
    final net = Provider.of<NetworkProvider>(context);
    final seeds = BootstrapService.getSeeds();

    return Scaffold(
      appBar: AppBar(title: const Text("Réseau")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 16,
                    color: net.isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    net.isConnected ? "Connecté" : "Déconnecté",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: net.isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  const Spacer(),
                  Text("${net.peers.length} pair(s)"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Serveur signaling : ${seeds.isNotEmpty ? seeds.first : 'aucun'}",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // --- Mon ID : QR code + copie, à partager pour être ajouté ---
          MyIdCard(myId: net.myId),
          const SizedBox(height: 16),

          // --- Ajouter un pair : coller son ID ou scanner son QR ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Ajouter un pair",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _idController,
                    decoration: const InputDecoration(
                      labelText: "Coller l'ID du pair",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addPeer(_idController.text),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!Platform.isWindows)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text("QR Scan"),
                            onPressed: _connecting ? null : _scanQr,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _connecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.person_add),
                          label: const Text("Ajouter"),
                          onPressed: _connecting
                              ? null
                              : () => _addPeer(_idController.text),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text("Pairs connectés :"),
          const SizedBox(height: 8),
          if (net.peers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text("Aucun pair pour le moment")),
            )
          else
            ...net.peers.map(
              (peerId) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: Text(peerId, overflow: TextOverflow.ellipsis),
                  subtitle: const Text("Connecté"),
                  // remplacer le bouton "Discuter" dans le ListTile des pairs connectés :
trailing: IconButton(
  icon: const Icon(Icons.chat_bubble_outline),
  tooltip: "Discuter",
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(peerId: peerId, peerName: peerId.substring(0, 12))),
    );
  },
),), 
              ),
            ),
        ],
      ),
    );
  }
}