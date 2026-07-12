// lib/features/bet/bets_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/bet/bet_model.dart';
import '../../shared/theme/colors.dart';
import '../wallet/wallet_screen.dart' show formatDoro;
import 'bet_provider.dart';
import 'create_bet_screen.dart';
import 'bet_detail_screen.dart';

class BetsListScreen extends StatefulWidget {
  const BetsListScreen({super.key});

  @override
  State<BetsListScreen> createState() => _BetsListScreenState();
}

class _BetsListScreenState extends State<BetsListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _shortId(String id) => id.length > 14 ? "${id.substring(0, 8)}…${id.substring(id.length - 4)}" : id;

  Widget _buildBetCard(BuildContext context, Bet bet, BetProvider provider) {
    final stakes = provider.stakesOf(bet.id);
    final totalPool = stakes.fold<BigInt>(BigInt.zero, (sum, s) => sum + s.amount);
    final creatorStr = bet.creatorId == provider.node.nodeId ? "Moi" : _shortId(bet.creatorId);

    // Determine status badge
    Color badgeColor;
    String statusText;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now < bet.stakingDeadline) {
      badgeColor = AppColors.success;
      statusText = "Mises Ouvertes";
    } else if (now < bet.votingDeadline) {
      badgeColor = Colors.amber;
      statusText = "Vote en Cours";
    } else {
      final tally = provider.tallyOf(bet);
      if (tally.isRefund) {
        badgeColor = AppColors.error;
        statusText = "Annulé/Remboursé";
      } else {
        badgeColor = Colors.deepPurpleAccent;
        statusText = "Terminé";
      }
    }

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BetDetailScreen(bet: bet),
            ),
          );
        },
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
                      bet.category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
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
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                bet.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              if (bet.description.isNotEmpty) ...[
                Text(
                  bet.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],
              Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Pool Total",
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatDoro(totalPool),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        "Créateur",
                        style: TextStyle(fontSize: 10, color: AppColors.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        creatorStr,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 13, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      now < bet.stakingDeadline
                          ? "Fin des mises : ${_formatDateTime(DateTime.fromMillisecondsSinceEpoch(bet.stakingDeadline))}"
                          : now < bet.votingDeadline
                              ? "Fin des votes : ${_formatDateTime(DateTime.fromMillisecondsSinceEpoch(bet.votingDeadline))}"
                              : "Pari clos",
                      style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBetsList(BuildContext context, List<Bet> bets, BetProvider provider) {
    if (bets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            const Text(
              "Aucun pari trouvé",
              style: TextStyle(fontSize: 16, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bets.length,
      itemBuilder: (context, index) => _buildBetCard(context, bets[index], provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BetProvider>();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Filter bets deterministically based on timestamps
    final allBets = provider.allBets;
    final openBets = allBets.where((b) => now < b.stakingDeadline).toList();
    final votingBets = allBets.where((b) => now >= b.stakingDeadline && now < b.votingDeadline).toList();
    final closedBets = allBets.where((b) => now >= b.votingDeadline).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          "Paris P2P",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.muted,
          dividerColor: Colors.white.withValues(alpha: 0.05),
          tabs: [
            Tab(text: "Ouverts (${openBets.length})"),
            Tab(text: "En vote (${votingBets.length})"),
            Tab(text: "Clos (${closedBets.length})"),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildBetsList(context, openBets, provider),
            _buildBetsList(context, votingBets, provider),
            _buildBetsList(context, closedBets, provider),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateBetScreen()),
          );
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          "Nouveau Pari",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
