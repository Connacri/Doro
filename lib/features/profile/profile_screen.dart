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
import '../../core/supabase/supabase_bootstrap.dart';
import '../../shared/theme/colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _loaded = false;
  bool _editing = false;

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
    if (!context.read<ProfileProvider>().available) {
      _showUnavailableSnack();
      return;
    }
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
    if (!context.read<ProfileProvider>().available) {
      _showUnavailableSnack();
      return;
    }
    try {
      await context.read<ProfileProvider>().pickCover();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de mettre à jour la couverture : $e")),
      );
    }
  }

  void _showUnavailableSnack() {
    final bootstrap = context.read<SupabaseBootstrap>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(bootstrap.errorMessage ?? "Profil indisponible pour le moment."),
        action: SnackBarAction(label: "Réessayer", onPressed: () => bootstrap.retry()),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (!context.read<ProfileProvider>().available) {
      _showUnavailableSnack();
      return;
    }
    await context.read<ProfileProvider>().saveNameAndBio(
          name: _nameCtrl.text,
          bio: _bioCtrl.text,
        );
    if (!context.mounted) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profil mis à jour")),
    );
  }

  /// Suppression de compte façon Facebook : programmée dans 30 jours,
  /// annulable en se reconnectant avant cette date — voir
  /// ProfileService.requestAccountDeletion().
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    if (!context.read<ProfileProvider>().available) {
      _showUnavailableSnack();
      return;
    }
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
    if (!context.mounted || date == null) return;
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
    final walletProv = context.watch<WalletProvider>();
    final net = context.watch<NetworkProvider>();
    final totalBalance = walletProv.wallets.fold<BigInt>(BigInt.zero, (sum, w) => sum + w.balance);
    final displayName = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : "Nouveau nœud Doro";

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (!provider.available) _Banner.warning(
                    text: provider.unavailableReason ?? "Profil (photos, nom, bio) indisponible pour le moment.",
                    actionLabel: "Réessayer",
                    onAction: () => context.read<SupabaseBootstrap>().retry(),
                  ),
                  if (deletion?.isPendingDeletion == true)
                    _Banner.danger(
                      text: "Ton compte sera supprimé le ${_formatDate(deletion!.scheduledFor!)}.",
                      actionLabel: "Annuler la suppression",
                      onAction: () async {
                        final ok = await context.read<ProfileProvider>().cancelAccountDeletion();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? "Suppression annulée." : "Impossible d'annuler.")),
                          );
                        }
                      },
                    ),

                  // ---- Hero header : couverture dégradée + avatar en anneau ----
                  _ProfileHero(
                    coverUrl: coverUrl,
                    avatarUrl: avatarUrl,
                    online: net.isConnected,
                    onEditCover: _pickCover,
                    onRemoveCover: coverUrl != null ? () => context.read<ProfileProvider>().removeCover() : null,
                    onEditAvatar: _pickAvatar,
                    onRemoveAvatar: avatarUrl != null ? () => context.read<ProfileProvider>().removeAvatar() : null,
                  ),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(displayName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: net.isConnected ? AppColors.success : Colors.grey),
                            const SizedBox(width: 6),
                            Text(net.isConnected ? "En ligne · nœud actif" : "Hors ligne",
                                style: TextStyle(fontSize: 13, color: net.isConnected ? AppColors.success : Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ---- Stat pills façon dashboard fintech ----
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(child: _StatPill(icon: Icons.account_balance_wallet_rounded, label: "Solde total", value: formatDoro(totalBalance), color: AppColors.primary)),
                        const SizedBox(width: 10),
                        Expanded(child: _StatPill(icon: Icons.hub_rounded, label: "Pairs connectés", value: "${net.peers.length}", color: AppColors.success)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        // ---- Carte bio / édition ----
                        _SectionCard(
                          child: _editing
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                                        const SizedBox(width: 8),
                                        const Text("Modifier mon profil", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _RoundedField(controller: _nameCtrl, label: "Nom affiché", maxLength: 40),
                                    const SizedBox(height: 12),
                                    _RoundedField(controller: _bioCtrl, label: "Bio / statut", maxLength: 140, maxLines: 3),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => setState(() => _editing = false),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                              side: const BorderSide(color: Colors.white24),
                                            ),
                                            child: const Text("Annuler"),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.primary,
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            ),
                                            onPressed: provider.saving ? null : () => _save(context),
                                            child: provider.saving
                                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                : const Text("Enregistrer"),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text("À propos", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => setState(() => _editing = true),
                                          icon: const Icon(Icons.edit_outlined, size: 16),
                                          label: const Text("Modifier"),
                                          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _bioCtrl.text.trim().isNotEmpty ? _bioCtrl.text.trim() : "Aucune bio pour l'instant — dis-en un peu plus sur toi.",
                                      style: TextStyle(fontSize: 14, height: 1.4, color: _bioCtrl.text.trim().isNotEmpty ? Colors.white70 : Colors.white38),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.public, size: 14, color: Colors.white38),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              "Visible par tous les pairs connectés au réseau — pas une information privée.",
                                              style: TextStyle(fontSize: 11.5, color: Colors.white38),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 14),

                        MyIdCardCompact(myId: provider.myAddress),
                        const SizedBox(height: 14),

                        _SectionCard(
                          padding: EdgeInsets.zero,
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.hub_outlined, color: AppColors.primary),
                              ),
                              title: const Text("Simulateur réseau multi-nœuds", style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text("Bac à sable DAG · chaos engine · marché OTC · gossip", style: TextStyle(fontSize: 12)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SimulatorScreen()),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        _WalletSection(),
                        const SizedBox(height: 14),

                        _PeersSection(),
                        const SizedBox(height: 14),

                        // --- Zone dangereuse ---
                        if (deletion?.isPendingDeletion != true)
                          _SectionCard(
                            padding: EdgeInsets.zero,
                            border: Colors.redAccent.withValues(alpha: 0.25),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                ),
                                title: const Text("Supprimer mon compte", style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: const Text("Suppression différée de 30 jours, annulable en se reconnectant.", style: TextStyle(fontSize: 12)),
                                onTap: () => _confirmDeleteAccount(context),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bannière d'état (avertissement / danger) en haut de l'écran.
class _Banner extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final Color color;
  final IconData icon;

  const _Banner({required this.text, required this.actionLabel, required this.onAction, required this.color, required this.icon});

  factory _Banner.warning({required String text, required String actionLabel, required VoidCallback onAction}) =>
      _Banner(text: text, actionLabel: actionLabel, onAction: onAction, color: const Color(0xFFB8860B), icon: Icons.cloud_off);

  factory _Banner.danger({required String text, required String actionLabel, required VoidCallback onAction}) =>
      _Banner(text: text, actionLabel: actionLabel, onAction: onAction, color: AppColors.error, icon: Icons.warning_amber_rounded);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
          const SizedBox(width: 4),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: onAction,
            child: Text(actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// En-tête façon "hero" : couverture en dégradé violet + avatar en anneau,
/// inspiré des interfaces de messagerie/réseau social modernes.
class _ProfileHero extends StatelessWidget {
  final String? coverUrl;
  final String? avatarUrl;
  final bool online;
  final VoidCallback onEditCover;
  final VoidCallback? onRemoveCover;
  final VoidCallback onEditAvatar;
  final VoidCallback? onRemoveAvatar;

  const _ProfileHero({
    required this.coverUrl,
    required this.avatarUrl,
    required this.online,
    required this.onEditCover,
    required this.onRemoveCover,
    required this.onEditAvatar,
    required this.onRemoveAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 168,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: coverUrl == null
                  ? const LinearGradient(
                      colors: [Color(0xFF6C5CE7), Color(0xFF2E1F63), Color(0xFF0F0F1A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              image: coverUrl != null ? DecorationImage(image: NetworkImage(coverUrl!), fit: BoxFit.cover) : null,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
            ),
            child: coverUrl != null
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
                      gradient: LinearGradient(
                        colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 14,
            top: 14,
            child: Row(children: [
              _GlassIconButton(icon: Icons.camera_alt_rounded, onTap: onEditCover, tooltip: "Changer la couverture"),
              if (onRemoveCover != null) ...[
                const SizedBox(width: 8),
                _GlassIconButton(icon: Icons.delete_outline_rounded, onTap: onRemoveCover!, tooltip: "Supprimer la couverture"),
              ],
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFFFF7AC6), Color(0xFF6C5CE7), Color(0xFF00D0FF)]),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
                      child: CircleAvatar(
                        radius: 46,
                        backgroundColor: AppColors.surface,
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                        child: avatarUrl == null ? const Icon(Icons.person, size: 44, color: Colors.white54) : null,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: online ? AppColors.success : Colors.grey,
                        border: Border.all(color: AppColors.background, width: 3),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: _GlassIconButton(icon: Icons.camera_alt_rounded, onTap: onEditAvatar, tooltip: "Changer la photo", small: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool small;
  const _GlassIconButton({required this.icon, required this.onTap, required this.tooltip, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(small ? 8 : 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, size: small ? 16 : 17, color: Colors.white),
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatPill({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white), overflow: TextOverflow.ellipsis),
                Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;
  const _SectionCard({required this.child, this.padding = const EdgeInsets.all(16), this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border ?? Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

class _RoundedField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int? maxLength;
  final int maxLines;
  const _RoundedField({required this.controller, required this.label, this.maxLength, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }
}

/// Version compacte de la carte d'ID/QR, dans le style du reste de l'écran.
class MyIdCardCompact extends StatelessWidget {
  final String myId;
  const MyIdCardCompact({super.key, required this.myId});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.qr_code_2_rounded, color: Colors.black87, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Mon ID réseau", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(myId, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white54), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
            tooltip: "Voir mon QR code",
            onPressed: () => showDialog(context: context, builder: (_) => Dialog(backgroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), child: Padding(padding: const EdgeInsets.all(16), child: MyIdCard(myId: myId)))),
          ),
        ],
      ),
    );
  }
}

class _WalletSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final walletProv = context.watch<WalletProvider>();
    final wallets = walletProv.wallets;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.account_balance_wallet, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text("Wallet(s)", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.key, size: 20, color: Colors.white54),
                tooltip: "Importer un wallet",
                onPressed: () => _importWallet(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (wallets.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text("Aucun wallet", style: TextStyle(color: Colors.white38))))
          else
            ...wallets.map((w) {
              final isGenesis = Genesis.isGenesisAddress(w.address);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isGenesis ? Colors.amber.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: isGenesis ? Border.all(color: Colors.amber.withValues(alpha: 0.3)) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(isGenesis ? Icons.stars : Icons.account_balance_wallet, size: 16, color: isGenesis ? Colors.amber : Colors.white54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(w.address, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis),
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isGenesis ? Colors.amber[300] : Colors.white)),
                  ],
                ),
              );
            }),
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
            const Text("Colle ta seed (64 caractères hex). Ne la partage jamais — et ne la colle jamais dans un chat.",
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
              final walletProv = context.read<WalletProvider>();
              try {
                final wallet = await walletProv.importWallet(seed);
                if (!context.mounted) return;
                final isFounder = Genesis.isGenesisAddress(wallet.address);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(isFounder
                      ? "Wallet fondateur reconnu — solde : ${formatDoro(wallet.balance)}"
                      : "Wallet importé — solde : ${formatDoro(wallet.balance)}"),
                  duration: const Duration(seconds: 4),
                ));
                await _offerCleanupIfNeeded(context, keepAddress: wallet.address);
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

  /// Après un import réussi, si d'autres wallets locaux sont vides
  /// (soldes à zéro — typiquement le wallet placeholder créé au tout
  /// premier lancement), propose de les retirer de la liste pour ne
  /// garder que le wallet qui vient d'être importé. Ne touche JAMAIS,
  /// même avec confirmation, à un wallet dont le solde est non nul —
  /// `WalletProvider.removeWallet` refuse silencieusement ce cas sans
  /// `force`, et on ne le propose même pas ici.
  Future<void> _offerCleanupIfNeeded(BuildContext context, {required String keepAddress}) async {
    if (!context.mounted) return;
    final walletProv = context.read<WalletProvider>();
    final redundant = walletProv.wallets.where((w) => w.address != keepAddress && w.balance == BigInt.zero).toList();
    if (redundant.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Nettoyer les wallets vides ?"),
        content: Text(
          redundant.length == 1
              ? "Tu as un autre wallet local à solde zéro. Le retirer de la liste sur cet appareil (aucune perte : il n'a aucun fonds)."
              : "Tu as ${redundant.length} autres wallets locaux à solde zéro. Les retirer de la liste sur cet appareil (aucune perte : ils n'ont aucun fonds).",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Garder")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Nettoyer")),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    for (final w in redundant) {
      await walletProv.removeWallet(w.address);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallet(s) vide(s) retiré(s).")));
    }
  }
}

class _PeersSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkProvider>();
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(net.isConnected ? Icons.wifi : Icons.wifi_off, size: 18, color: net.isConnected ? AppColors.success : AppColors.error),
              const SizedBox(width: 8),
              Text(net.isConnected ? "Connecté" : "Déconnecté", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: net.isConnected ? AppColors.success : AppColors.error)),
              const Spacer(),
              Text("${net.peers.length} pair(s)", style: const TextStyle(fontSize: 13, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 12),
          if (net.peers.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text("Aucun pair connecté", style: TextStyle(color: Colors.white38))))
          else
            ...net.peers.map((peerId) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(child: Text(peerId, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white54),
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
    );
  }
}
