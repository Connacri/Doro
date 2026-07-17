// lib/features/prediction/prediction_markets_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/prediction/prediction_event.dart';
import '../../shared/theme/colors.dart';
import '../wallet/wallet_screen.dart' show formatDoro;
import '../wallet/wallet_provider.dart';
import '../../core/market/order_model.dart' show OrderSide;
import 'prediction_market_provider.dart';
import 'create_prediction_screen.dart';
import 'prediction_detail_screen.dart';

class PredictionMarketsScreen extends StatefulWidget {
  const PredictionMarketsScreen({super.key});

  @override
  State<PredictionMarketsScreen> createState() => _PredictionMarketsScreenState();
}

class _PredictionMarketsScreenState extends State<PredictionMarketsScreen> with SingleTickerProviderStateMixin {
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

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Comment ça marche ?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
            const SizedBox(height: 16),
            _buildHelpItem(Icons.add_shopping_cart, "Minting", "Déposez 1 DORO pour recevoir 1 part OUI et 1 part NON. L'escrow sécurise les fonds."),
            const SizedBox(height: 12),
            _buildHelpItem(Icons.swap_horiz, "Trading", "Achetez ou vendez des parts individuelles à d'autres utilisateurs via le carnet d'ordres."),
            const SizedBox(height: 12),
            _buildHelpItem(Icons.verified, "Résolution", "L'oracle certifie l'issue réelle. 1 part gagnante devient échangeable contre 1 DORO."),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Compris"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String _shortId(String id) => id.length > 14 ? "${id.substring(0, 8)}…${id.substring(id.length - 4)}" : id;

  double _getYesPrice(String eventId, PredictionMarketProvider provider) {
    final orders = provider.openShareOrdersFor(eventId);
    final yesSells = orders.where((o) => o.outcome == "yes" && o.side == OrderSide.sell).toList()
      ..sort((a, b) => a.pricePerShare.compareTo(b.pricePerShare));
    if (yesSells.isNotEmpty) return yesSells.first.pricePerShare.toDouble() / 1e18;
    
    final yesBuys = orders.where((o) => o.outcome == "yes" && o.side == OrderSide.buy).toList()
      ..sort((a, b) => b.pricePerShare.compareTo(a.pricePerShare));
    if (yesBuys.isNotEmpty) return yesBuys.first.pricePerShare.toDouble() / 1e18;

    return 0.50; // default 50%
  }

  void _deleteEvent(BuildContext context, PredictionEvent event, PredictionMarketProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Supprimer le marché", style: TextStyle(color: AppColors.text)),
        content: const Text("Cette action est irréversible.", style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Supprimer", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await provider.deleteEvent(event);
    if (ok) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Marché supprimé !")));
    } else {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.lastError ?? "Échec suppression")));
    }
  }

  void _editEvent(BuildContext context, PredictionEvent event, PredictionMarketProvider provider) async {
    final updated = await Navigator.push<PredictionEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePredictionScreen(editEvent: event),
      ),
    );
    if (updated != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Marché mis à jour !")),
      );
    }
  }

  Widget _buildEventCard(BuildContext context, PredictionEvent event, PredictionMarketProvider provider) {
    final myAddr = context.read<WalletProvider>().wallets.isNotEmpty
        ? context.read<WalletProvider>().wallets.last.address
        : "";
    final isCreator = myAddr == event.creatorId;
    final yesPrice = _getYesPrice(event.id, provider);
    final noPrice = 1.0 - yesPrice;
    final yesPercent = (yesPrice * 100).toStringAsFixed(0);
    final noPercent = (noPrice * 100).toStringAsFixed(0);

    final positionYes = provider.positionFor(event.id, yes: true);
    final positionNo = provider.positionFor(event.id, yes: false);
    final totalShares = positionYes.shares + positionNo.shares;

    // Get total escrow value of the event
    final eventPositions = provider.node.outcomePositionRepo.positionsForEvent(event.id);
    final totalSharesMinted = eventPositions.fold<BigInt>(BigInt.zero, (sum, p) => sum + p.shares) ~/ BigInt.from(2);
    final totalEscrow = totalSharesMinted * BigInt.from(10).pow(18);

    Color statusColor;
    String statusText;
    if (event.isResolved) {
      statusColor = Colors.deepPurpleAccent;
      statusText = "RÉSOLU : ${event.winningOutcome == PredictionOutcome.yes ? 'OUI' : 'NON'}";
    } else if (DateTime.now().millisecondsSinceEpoch >= event.closesAt) {
      statusColor = Colors.amber;
      statusText = "ARBITRAGE EN COURS";
    } else {
      statusColor = AppColors.success;
      statusText = "LIVE";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PredictionDetailScreen(event: event),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar with Status
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white.withValues(alpha: 0.03),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (totalShares > BigInt.zero)
                          Row(
                            children: [
                              const Icon(Icons.wallet, size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              const Text(
                                "DÉTENTEUR",
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary),
                              ),
                            ],
                          ),
                        if (!event.isResolved && isCreator)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _editEvent(context, event, provider),
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 12),
                                  child: Icon(Icons.edit_outlined, size: 16, color: AppColors.muted),
                                ),
                              ),
                              InkWell(
                                onTap: () => _deleteEvent(context, event, provider),
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 12),
                                  child: Icon(Icons.delete_outline, size: 16, color: AppColors.muted),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.question,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.text, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    
                    // Buttons with improved design
                    Row(
                      children: [
                        Expanded(
                          child: _buildProbabilityButton(
                            label: "OUI",
                            percent: "$yesPercent%",
                            color: Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildProbabilityButton(
                            label: "NON",
                            percent: "$noPercent%",
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Footer Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatItem("LIQUIDITÉ", formatDoro(totalEscrow)),
                        _buildStatItem("ORACLE", _shortId(event.oracleAddress)),
                        _buildStatItem("ÉCHÉANCE", _formatDateTime(DateTime.fromMillisecondsSinceEpoch(event.closesAt)).split(' à ')[0]),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.text)),
      ],
    );
  }

  Widget _buildProbabilityButton({required String label, required String percent, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 13),
          ),
          Text(
            percent,
            style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 18),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PredictionMarketProvider>();

    final open = provider.openEvents;
    final resolved = provider.resolvedEvents;

    // Filter events where current user holds positions
    final allEvents = [...open, ...resolved];
    final portfolio = allEvents.where((e) {
      final posYes = provider.positionFor(e.id, yes: true);
      final posNo = provider.positionFor(e.id, yes: false);
      return posYes.shares > BigInt.zero || posNo.shares > BigInt.zero;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            const Icon(Icons.auto_graph, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            const Text("PREDICT", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 22)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: AppColors.muted),
            onPressed: () => _showHelp(context),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.muted,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: "MARCHÉS (${open.length})"),
                Tab(text: "RÉSOLUS (${resolved.length})"),
                Tab(text: "PORTFOLIO (${portfolio.length})"),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildMarketsList(open, provider),
            _buildMarketsList(resolved, provider),
            _buildMarketsList(portfolio, provider),
          ],
        ),
      ),
      floatingActionButton: Container(
        height: 60,
        width: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [AppColors.primary, Color(0xFF8E78FF)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatePredictionScreen()),
            );
          },
          icon: const Icon(Icons.add, color: Colors.white, size: 24),
          label: const Text(
            "CRÉER",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildMarketsList(List<PredictionEvent> events, PredictionMarketProvider provider) {
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.query_stats, size: 64, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            const Text("Aucun marché disponible", style: TextStyle(fontSize: 15, color: AppColors.muted)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (ctx, idx) => _buildEventCard(context, events[idx], provider),
    );
  }
}
