// lib/features/bet/bet_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bet/bet_model.dart';
import '../../shared/theme/colors.dart';
import '../wallet/wallet_screen.dart' show formatDoro;
import '../wallet/wallet_provider.dart';
import 'bet_provider.dart';

class BetDetailScreen extends StatefulWidget {
  final Bet bet;
  const BetDetailScreen({super.key, required this.bet});

  @override
  State<BetDetailScreen> createState() => _BetDetailScreenState();
}

class _BetDetailScreenState extends State<BetDetailScreen> {
  final _stakeAmountCtrl = TextEditingController();
  String? _selectedOption;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Trigger settlement check automatically upon opening the detail screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BetProvider>().settleIfDue(widget.bet);
    });
  }

  @override
  void dispose() {
    _stakeAmountCtrl.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _shortId(String id) => id.length > 14 ? "${id.substring(0, 8)}…${id.substring(id.length - 4)}" : id;

  Future<void> _placeStake(BetProvider provider, BigInt myBalance) async {
    if (_selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez choisir une option.")),
      );
      return;
    }
    final amountStr = _stakeAmountCtrl.text.trim();
    final parsedAmount = double.tryParse(amountStr);
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez entrer un montant valide.")),
      );
      return;
    }

    final amount = BigInt.from(parsedAmount * 1e18);
    if (amount < widget.bet.minStake) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Mise minimale : ${formatDoro(widget.bet.minStake)}")),
      );
      return;
    }

    if (amount > myBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Solde insuffisant pour cette adresse.")),
      );
      return;
    }

    setState(() => _isLoading = true);
    final ok = await provider.stake(bet: widget.bet, optionLabel: _selectedOption!, amount: amount);
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mise enregistrée avec succès !")),
      );
      _stakeAmountCtrl.clear();
      setState(() => _selectedOption = null);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : ${provider.lastError ?? 'Échec'}")),
      );
    }
  }

  Future<void> _vote(BetProvider provider, String option) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer le vote"),
        content: Text("Es-tu sûr que l'issue réelle de ce pari est : \"$option\" ? Ce vote ne pourra plus être modifié."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirmer")),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);
    final ok = await provider.vote(bet: widget.bet, votedOptionLabel: option);
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vote enregistré et diffusé !")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : ${provider.lastError ?? 'Échec'}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BetProvider>();
    final walletProvider = context.watch<WalletProvider>();

    final myNodeId = provider.node.nodeId;
    final stakes = provider.stakesOf(widget.bet.id);
    final votes = provider.votesOf(widget.bet.id);
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get specific node balance (since staking comes from identity.nodeId)
    final myNodeWallet = walletProvider.wallets.firstWhere(
      (w) => w.address == myNodeId,
      orElse: () => walletProvider.wallets.isNotEmpty
          ? walletProvider.wallets.first
          : throw StateError("Aucun wallet disponible"),
    );
    final myBalance = myNodeWallet.balance;

    final hasStaked = stakes.any((s) => s.stakerId == myNodeId);
    final myStake = stakes.firstWhere(
      (s) => s.stakerId == myNodeId,
      orElse: () => BetStake(id: '', betId: '', optionLabel: '', stakerId: '', stakerPublicKey: '', amount: BigInt.zero, timestamp: 0, signature: ''),
    );

    final hasVoted = votes.any((v) => v.voterId == myNodeId);

    // Calculate distributions
    final totalStaked = stakes.fold<BigInt>(BigInt.zero, (sum, s) => sum + s.amount);
    final optionDistribution = <String, BigInt>{};
    for (final opt in widget.bet.optionLabels) {
      optionDistribution[opt] = BigInt.zero;
    }
    for (final s in stakes) {
      optionDistribution[s.optionLabel] = (optionDistribution[s.optionLabel] ?? BigInt.zero) + s.amount;
    }

    // Determine status badge
    Color badgeColor;
    String statusText;
    if (now < widget.bet.stakingDeadline) {
      badgeColor = AppColors.success;
      statusText = "Mises Ouvertes";
    } else if (now < widget.bet.votingDeadline) {
      badgeColor = Colors.amber;
      statusText = "Vote en Cours";
    } else {
      final tally = provider.tallyOf(widget.bet);
      if (tally.isRefund) {
        badgeColor = AppColors.error;
        statusText = "Annulé/Remboursé";
      } else {
        badgeColor = Colors.deepPurpleAccent;
        statusText = "Terminé (Gagnant : ${tally.winningOptionLabel})";
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text("Détails du Pari", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info Card
                  Card(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.bet.category.toUpperCase(),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.bet.title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
                          ),
                          const SizedBox(height: 8),
                          if (widget.bet.description.isNotEmpty) ...[
                            Text(
                              widget.bet.description,
                              style: const TextStyle(fontSize: 14, color: AppColors.muted),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Divider(color: Colors.white.withValues(alpha: 0.05)),
                          const SizedBox(height: 12),
                          _buildDetailRow("Mise minimale", formatDoro(widget.bet.minStake)),
                          const SizedBox(height: 8),
                          _buildDetailRow("Pool Total", formatDoro(totalStaked)),
                          const SizedBox(height: 8),
                          _buildDetailRow("Créateur", _shortId(widget.bet.creatorId)),
                          const SizedBox(height: 8),
                          _buildDetailRow("Frais plateforme", "${widget.bet.feeBasisPoints / 100}%"),
                          const SizedBox(height: 8),
                          _buildDetailRow("Fin des mises", _formatDateTime(DateTime.fromMillisecondsSinceEpoch(widget.bet.stakingDeadline))),
                          const SizedBox(height: 8),
                          _buildDetailRow("Fin des votes", _formatDateTime(DateTime.fromMillisecondsSinceEpoch(widget.bet.votingDeadline))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Distribution Chart Card
                  Card(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Répartition des Mises",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                          ),
                          const SizedBox(height: 16),
                          ...widget.bet.optionLabels.map((opt) {
                            final amount = optionDistribution[opt] ?? BigInt.zero;
                            final percent = totalStaked == BigInt.zero ? 0.0 : amount.toDouble() / totalStaked.toDouble();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(opt, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text)),
                                      Text(
                                        "${formatDoro(amount)} (${(percent * 100).toStringAsFixed(1)}%)",
                                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      minHeight: 8,
                                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                                      color: AppColors.primary,
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
                  const SizedBox(height: 20),

                  // Actions Section
                  if (now < widget.bet.stakingDeadline) ...[
                    // Staking section
                    Card(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Placer une mise", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
                            const SizedBox(height: 8),
                            Text("Mon solde disponible : ${formatDoro(myBalance)}", style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              children: widget.bet.optionLabels.map((opt) {
                                final isSelected = _selectedOption == opt;
                                return ChoiceChip(
                                  label: Text(opt, style: TextStyle(color: isSelected ? Colors.white : AppColors.muted)),
                                  selected: isSelected,
                                  selectedColor: AppColors.primary,
                                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                                  onSelected: (selected) {
                                    setState(() => _selectedOption = selected ? opt : null);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _stakeAmountCtrl,
                              style: const TextStyle(color: AppColors.text),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: "Montant à miser (DORO)",
                                labelStyle: const TextStyle(color: AppColors.muted),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: hasStaked ? null : () => _placeStake(provider, myBalance),
                                child: Text(hasStaked ? "Déjà misé (${formatDoro(myStake.amount)} sur ${myStake.optionLabel})" : "Miser"),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else if (now < widget.bet.votingDeadline) ...[
                    // Voting Section
                    Card(
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Voter pour le résultat réel", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
                            const SizedBox(height: 8),
                            const Text(
                              "Pour assurer un arbitrage honnête, votez pour l'option qui s'est réellement produite. Le résultat est déterminé par la majorité des stakers.",
                              style: TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                            const SizedBox(height: 16),
                            if (!hasStaked)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text("Seuls les participants ayant misé peuvent voter.", style: TextStyle(color: AppColors.error, fontSize: 13)),
                                ),
                              )
                            else if (hasVoted)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text("Vous avez déjà voté pour ce pari.", style: TextStyle(color: AppColors.success, fontSize: 13)),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                children: widget.bet.optionLabels.map((opt) {
                                  return ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                      foregroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () => _vote(provider, opt),
                                    child: Text("Voter \"$opt\""),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Participants List Card
                  Card(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Participants & Mises",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                          ),
                          const SizedBox(height: 12),
                          if (stakes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text("Aucun participant pour l'instant.", style: TextStyle(color: AppColors.muted)),
                            )
                          else
                            ...stakes.map((s) {
                              final isMe = s.stakerId == myNodeId;
                              final entityList = provider.node.betStakeRepo.entitiesByBet(widget.bet.id);
                              final stakeEntity = entityList.firstWhere(
                                (e) => e.stakeId == s.id,
                                orElse: () => throw StateError("Stake non trouvé en DB"),
                              );

                              // Determine status display
                              Widget statusWidget;
                              if (now < widget.bet.votingDeadline) {
                                statusWidget = const Text("Engagé", style: TextStyle(color: AppColors.success, fontSize: 12));
                              } else {
                                final tally = provider.tallyOf(widget.bet);
                                if (tally.isRefund) {
                                  statusWidget = const Text("Remboursé", style: TextStyle(color: Colors.grey, fontSize: 12));
                                } else if (s.optionLabel == tally.winningOptionLabel) {
                                  statusWidget = const Text("Gagnant", style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold));
                                } else if (stakeEntity.payoutTxId != null) {
                                  statusWidget = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check, size: 12, color: Colors.greenAccent),
                                      const SizedBox(width: 4),
                                      Text("Payé", style: TextStyle(color: Colors.greenAccent.shade400, fontSize: 11)),
                                    ],
                                  );
                                } else if (stakeEntity.defaulted) {
                                  statusWidget = Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text("Défaillant", style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.bold)),
                                  );
                                } else {
                                  statusWidget = const Text("En attente de paiement", style: TextStyle(color: Colors.amber, fontSize: 11));
                                }
                              }

                              return Container(
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                                ),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    isMe ? "Moi (${_shortId(s.stakerId)})" : _shortId(s.stakerId),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "Mise : ${formatDoro(s.amount)} sur \"${s.optionLabel}\"",
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                  ),
                                  trailing: statusWidget,
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text)),
      ],
    );
  }
}
