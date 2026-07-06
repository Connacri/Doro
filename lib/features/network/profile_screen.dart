import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/bootstrap/bootstrap_service.dart';
import '../../core/wallet/genesis.dart';
import '../wallet/wallet_provider.dart';
import '../wallet/wallet_screen.dart';
import 'network_provider.dart';
import 'qr_scan_screen.dart';
import '../chat/chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  void _copyId(BuildContext context, String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("ID copié dans le presse-papiers")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkProvider>();
    final walletProv = context.watch<WalletProvider>();
    final seeds = BootstrapService.getSeeds();
    final wallets = walletProv.wallets;

    return Scaffold(
      appBar: AppBar(title: const Text("Profil")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Statut connexion ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 16, color: net.isConnected ? Colors.green : Colors.red),
                  const SizedBox(width: 12),
                  Text(
                    net.isConnected ? "Connecté" : "Déconnecté",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: net.isConnected ? Colors.green : Colors.red),
                  ),
                  const Spacer(),
                  Text("${net.peers.length} pair(s)"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Mon Identité (QR + Node ID) ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text("Mon identité", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: QrImageView(data: net.myId, version: QrVersions.auto, size: 180, backgroundColor: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(net.myId, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(icon: const Icon(Icons.copy, size: 18), tooltip: "Copier mon ID", onPressed: () => _copyId(context, net.myId)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Wallet(s) ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 20),
                      const SizedBox(width: 8),
                      const Text("Wallet(s)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.key, size: 20),
                        tooltip: "Importer un wallet",
                        onPressed: () => _importWallet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (wallets.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text("Aucun wallet", style: TextStyle(color: Colors.grey))))
                  else
                    ...wallets.map((w) {
                      final isGenesis = Genesis.isGenesisAddress(w.address);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isGenesis ? Colors.amber.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: isGenesis ? Border.all(color: Colors.amber.withValues(alpha: 0.3)) : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(isGenesis ? Icons.stars : Icons.account_balance_wallet, size: 16, color: isGenesis ? Colors.amber : null),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(w.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                                if (isGenesis)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                    child: const Text("Fondateur", style: TextStyle(fontSize: 10, color: Colors.amber)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              formatDoro(w.balance),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isGenesis ? Colors.amber[800] : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Réseau ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Réseau", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text("Serveur signaling : ${seeds.isNotEmpty ? seeds.first : 'aucun'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  const Text("Ajouter un pair", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _idController,
                    decoration: const InputDecoration(labelText: "Coller l'ID du pair", border: OutlineInputBorder()),
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
                      if (!Platform.isWindows) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _connecting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.person_add),
                          label: const Text("Ajouter"),
                          onPressed: _connecting ? null : () => _addPeer(_idController.text),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Pairs connectés ---
          const Text("Pairs connectés :", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (net.peers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text("Aucun pair pour le moment", style: TextStyle(color: Colors.grey))),
            )
          else
            ...net.peers.map(
              (peerId) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: Text(peerId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  subtitle: const Text("Connecté"),
                  trailing: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline),
                    tooltip: "Discuter",
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatScreen(peerId: peerId, peerName: peerId.substring(0, 12))),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _importWallet(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Importer un wallet"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Colle ta seed (64 caractères hex). Ne la partage jamais.",
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Seed (64 caractères hex)", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Annuler")),
          FilledButton(
            onPressed: () async {
              final seed = controller.text.trim();
              if (seed.isEmpty) return;
              Navigator.of(ctx).pop();
              final provider = context.read<WalletProvider>();
              try {
                await provider.importWallet(seed);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallet importé")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import impossible : $e")));
                }
              }
            },
            child: const Text("Importer"),
          ),
        ],
      ),
    );
  }
}
