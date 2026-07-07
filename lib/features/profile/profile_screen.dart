import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'profile_provider.dart';
import '../network/my_id_card.dart';
import '../network/network_provider.dart';
import '../wallet/wallet_provider.dart';
import '../wallet/wallet_screen.dart';
import '../../core/wallet/genesis.dart';
import '../chat/chat_screen.dart';
import '../simulator/simulator_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _loadFromProvider(ProfileProvider provider) {
    if (_loaded) return;
    _loaded = true;
    _nameCtrl.text = provider.mine?.displayName ?? "";
    _bioCtrl.text = provider.mine?.bio ?? "";
  }

  Future<void> _pickPhoto() async {
    try {
      await context.read<ProfileProvider>().pickPhoto();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de mettre à jour la photo : $e")),
      );
    }
  }

  Future<void> _save(BuildContext context) async {
    await context.read<ProfileProvider>().saveNameAndBio(
          name: _nameCtrl.text,
          bio: _bioCtrl.text,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profil mis à jour et diffusé au réseau")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    _loadFromProvider(provider);
    final photoPath = provider.mine?.photoPath ?? "";
    final hasPhoto = photoPath.isNotEmpty && File(photoPath).existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text("Mon profil")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    backgroundImage: hasPhoto ? FileImage(File(photoPath)) : null,
                    child: hasPhoto ? null : const Icon(Icons.person, size: 56),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _pickPhoto,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: _pickPhoto, child: const Text("Changer la photo")),
                if (hasPhoto)
                  TextButton(
                    onPressed: () => context.read<ProfileProvider>().removePhoto(),
                    child: const Text("Supprimer", style: TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: "Nom affiché",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              maxLength: 140,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Bio / statut",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: provider.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text("Enregistrer et diffuser"),
                onPressed: provider.saving ? null : () => _save(context),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Ce nom, cette bio et cette photo sont visibles par tous les pairs "
              "connectés au réseau — ce n'est pas une information privée.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            MyIdCard(myId: provider.myAddress),
            const SizedBox(height: 24),

            // --- Simulateur réseau multi-nœuds (port de index.html) ---
            Card(
              child: ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: const Text("Simulateur réseau multi-nœuds"),
                subtitle: const Text("Bac à sable DAG · chaos engine · marché OTC · gossip"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SimulatorScreen()),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- Wallet(s) ---
            _WalletSection(),
            const SizedBox(height: 12),

            // --- Pairs connectés ---
            _PeersSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _WalletSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final walletProv = context.watch<WalletProvider>();
    final wallets = walletProv.wallets;
    return Card(
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
                      Text(formatDoro(w.balance),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isGenesis ? Colors.amber[800] : null)),
                    ],
                  ),
                );
              }),
          ],
        ),
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
            TextField(controller: controller, obscureText: true,
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
              try {
                await context.read<WalletProvider>().importWallet(seed);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallet importé")));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import impossible : $e")));
              }
            },
            child: const Text("Importer"),
          ),
        ],
      ),
    );
  }
}

class _PeersSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(net.isConnected ? Icons.wifi : Icons.wifi_off, size: 20, color: net.isConnected ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(net.isConnected ? "Connecté" : "Déconnecté", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: net.isConnected ? Colors.green : Colors.red)),
                const Spacer(),
                Text("${net.peers.length} pair(s)", style: const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            if (net.peers.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text("Aucun pair connecté", style: TextStyle(color: Colors.grey))))
            else
              ...net.peers.map((peerId) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(peerId, style: const TextStyle(fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis)),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      tooltip: "Discuter",
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ChatScreen(peerId: peerId, peerName: peerId.substring(0, 12))),
                      ),
                    ),
                  ],
                ),
              )),
          ],
        ),
      ),
    );
  }
}
