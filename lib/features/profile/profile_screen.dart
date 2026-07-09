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
    if (provider.mine == null) return; // pas encore chargé depuis Supabase
    _loaded = true;
    _nameCtrl.text = (provider.mine?['display_name'] as String?) ?? "";
    _bioCtrl.text = (provider.mine?['bio'] as String?) ?? "";
  }

  Future<void> _pickAvatar() async {
    try {
      await context.read<ProfileProvider>().pickAvatar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de mettre à jour la photo : $e")),
      );
    }
  }

  Future<void> _pickCover() async {
    try {
      await context.read<ProfileProvider>().pickCover();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de mettre à jour la couverture : $e")),
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
      const SnackBar(content: Text("Profil mis à jour")),
    );
  }

  /// Suppression de compte façon Facebook : programmée dans 30 jours,
  /// annulable en se reconnectant avant cette date — voir
  /// ProfileService.requestAccountDeletion().
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ton compte ?"),
        content: const Text(
          "Ton compte sera désactivé immédiatement puis définitivement supprimé "
          "dans 30 jours (profil, messages, amis, wallet lié). "
          "Tu peux annuler à tout moment avant cette date en te reconnectant.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer mon compte"),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final date = await context.read<ProfileProvider>().requestAccountDeletion();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Compte programmé pour suppression le ${_formatDate(date)}."),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _formatDate(DateTime d) => "${d.day}/${d.month}/${d.year}";

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();
    _loadFromProvider(provider);
    final avatarUrl = provider.avatarUrl;
    final coverUrl = provider.coverUrl;
    final deletion = provider.deletionStatus;

    return Scaffold(
      appBar: AppBar(title: const Text("Mon profil")),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (deletion?.isPendingDeletion == true)
              Container(
                width: double.infinity,
                color: Colors.red.shade900,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Ton compte sera supprimé le ${_formatDate(deletion!.scheduledFor!)}.",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white24),
                      onPressed: () async {
                        final ok = await context.read<ProfileProvider>().cancelAccountDeletion();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? "Suppression annulée." : "Impossible d'annuler.")),
                          );
                        }
                      },
                      child: const Text("Annuler la suppression"),
                    ),
                  ],
                ),
              ),

            // ---- Couverture façon Facebook ----
            Stack(
              children: [
                Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    image: coverUrl != null ? DecorationImage(image: NetworkImage(coverUrl), fit: BoxFit.cover) : null,
                  ),
                  child: coverUrl == null
                      ? Center(child: Icon(Icons.image_outlined, size: 40, color: Theme.of(context).disabledColor))
                      : null,
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Row(children: [
                    _CircleActionButton(icon: Icons.camera_alt, onTap: _pickCover, tooltip: "Changer la couverture"),
                    if (coverUrl != null) ...[
                      const SizedBox(width: 8),
                      _CircleActionButton(
                        icon: Icons.delete_outline,
                        onTap: () => context.read<ProfileProvider>().removeCover(),
                        tooltip: "Supprimer la couverture",
                      ),
                    ],
                  ]),
                ),
                Positioned(
                  left: 16,
                  bottom: -44,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                        child: CircleAvatar(
                          radius: 44,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null ? const Icon(Icons.person, size: 44) : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: _CircleActionButton(icon: Icons.camera_alt, onTap: _pickAvatar, tooltip: "Changer la photo", small: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 56),
            if (avatarUrl != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.read<ProfileProvider>().removeAvatar(),
                    child: const Text("Supprimer la photo", style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
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
                      label: const Text("Enregistrer"),
                      onPressed: provider.saving ? null : () => _save(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Ce nom, cette bio et ces photos sont visibles par tous les pairs "
                      "connectés au réseau — ce n'est pas une information privée.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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

                  // --- Zone dangereuse ---
                  if (deletion?.isPendingDeletion != true)
                    Card(
                      color: Colors.red.withValues(alpha: 0.06),
                      child: ListTile(
                        leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        title: const Text("Supprimer mon compte"),
                        subtitle: const Text("Suppression différée de 30 jours, annulable en se reconnectant."),
                        onTap: () => _confirmDeleteAccount(context),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool small;
  const _CircleActionButton({required this.icon, required this.onTap, required this.tooltip, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(small ? 8 : 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
          ),
          child: Icon(icon, size: small ? 18 : 16, color: Colors.white),
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
