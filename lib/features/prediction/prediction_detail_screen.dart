import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/prediction/prediction_event.dart';
import '../../core/prediction/share_order.dart';
import '../../core/market/order_model.dart' show OrderSide;
import '../../shared/theme/colors.dart';
import '../wallet/wallet_screen.dart' show formatDoro;
import '../wallet/wallet_provider.dart';
import 'prediction_market_provider.dart';
import 'create_prediction_screen.dart';

class PredictionDetailScreen extends StatefulWidget {
  final PredictionEvent event;
  const PredictionDetailScreen({super.key, required this.event});

  @override
  State<PredictionDetailScreen> createState() => _PredictionDetailScreenState();
}

class _PredictionDetailScreenState extends State<PredictionDetailScreen>
    with SingleTickerProviderStateMixin {
  final _mintCtrl = TextEditingController();
  final _orderSharesCtrl = TextEditingController();
  final _orderPriceCtrl = TextEditingController();

  String _selectedOutcome = "yes";
  bool _isLoading = false;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _mintCtrl.dispose();
    _orderSharesCtrl.dispose();
    _orderPriceCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} "
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  String _shortId(String id) =>
      id.length > 14 ? "${id.substring(0, 8)}…${id.substring(id.length - 4)}" : id;

  double _getYesPrice(String eventId, List<ShareOrder> orders) {
    final yesSells = orders
        .where((o) => o.outcome == "yes" && o.side == OrderSide.sell && o.isOpen)
        .toList()
      ..sort((a, b) => a.pricePerShare.compareTo(b.pricePerShare));
    if (yesSells.isNotEmpty) return yesSells.first.pricePerShare.toDouble() / 1e18;
    final yesBuys = orders
        .where((o) => o.outcome == "yes" && o.side == OrderSide.buy && o.isOpen)
        .toList()
      ..sort((a, b) => b.pricePerShare.compareTo(a.pricePerShare));
    if (yesBuys.isNotEmpty) return yesBuys.first.pricePerShare.toDouble() / 1e18;
    return 0.50;
  }

  Future<void> _mint(PredictionMarketProvider p) async {
    final raw = _mintCtrl.text.trim();
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) {
      _snack("Quantité invalide.");
      return;
    }
    final shares = BigInt.from(parsed * 1e18);
    setState(() => _isLoading = true);
    final ok = await p.buyCompleteSet(event: widget.event, shares: shares);
    setState(() => _isLoading = false);
    if (ok) {
      _snack("Parts OUI+NON émises !");
      _mintCtrl.clear();
    } else {
      _snack(p.lastError ?? "Échec mint");
    }
  }

  Future<void> _placeOrder(PredictionMarketProvider p, String myAddress) async {
    final rawAmount = _orderSharesCtrl.text.trim();
    final rawPrice = _orderPriceCtrl.text.trim();
    final parsedAmount = double.tryParse(rawAmount.replaceAll(',', '.'));
    final parsedPrice = double.tryParse(rawPrice.replaceAll(',', '.'));
    if (parsedAmount == null || parsedAmount <= 0 || parsedPrice == null || parsedPrice <= 0 || parsedPrice >= 1.0) {
      _snack("Prix ou quantité invalide (0 < prix < 1 DORO).");
      return;
    }
    final shares = BigInt.from(parsedAmount * 1e18);
    final price = BigInt.from(parsedPrice * 1e18);

    setState(() => _isLoading = true);
    final order = await p.publishShareOrder(
      eventId: widget.event.id,
      outcome: _selectedOutcome,
      side: OrderSide.sell,
      shares: shares,
      pricePerShare: price,
    );
    setState(() => _isLoading = false);
    if (order != null) {
      _snack("Ordre de vente publié !");
      _orderSharesCtrl.clear();
      _orderPriceCtrl.clear();
    } else {
      _snack(p.lastError ?? "Échec");
    }
  }

  Future<void> _fillOrder(PredictionMarketProvider p, ShareOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("Acheter des parts", style: const TextStyle(color: AppColors.text)),
        content: Text(
          "Acheter ${_fmtShares(order.remaining)} parts ${order.outcome.toUpperCase()} "
          "à ${_fmtPrice(order.pricePerShare)} DORO/part ?\n"
          "Total : ${formatDoro((order.remaining * order.pricePerShare) ~/ BigInt.from(10).pow(18))}",
          style: const TextStyle(color: AppColors.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Acheter")),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    setState(() => _isLoading = true);
    final txId = await p.fillShareOrder(order: order, sharesToFill: order.remaining);
    setState(() => _isLoading = false);
    if (txId != null) {
      _snack("Achat exécuté ! parts créditées.");
    } else {
      _snack(p.lastError ?? "Échec");
    }
  }

  Future<void> _resolve(PredictionMarketProvider p, PredictionOutcome o) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Trancher", style: TextStyle(color: AppColors.text)),
        content: Text("Confirmer : $o ?", style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirmer")),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    setState(() => _isLoading = true);
    final ok = await p.resolve(event: widget.event, outcome: o);
    setState(() => _isLoading = false);
    if (ok) {
      _snack("Marché résolu !");
    } else {
      _snack(p.lastError ?? "Échec");
    }
  }

  Future<void> _deleteEvent(PredictionMarketProvider p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Supprimer le marché", style: TextStyle(color: AppColors.text)),
        content: const Text("Cette action est irréversible. Toutes les parts et ordres seront perdus.",
            style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Supprimer", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isLoading = true);
    final ok = await p.deleteEvent(widget.event);
    setState(() => _isLoading = false);
    if (ok && mounted) {
      _snack("Marché supprimé !");
      Navigator.pop(context);
    } else {
      _snack(p.lastError ?? "Échec suppression");
    }
  }

  Future<void> _editEvent(PredictionMarketProvider p) async {
    final updated = await Navigator.push<PredictionEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePredictionScreen(editEvent: widget.event),
      ),
    );
    if (updated != null && mounted) {
      _snack("Marché mis à jour !");
    }
  }

  Future<void> _claim(PredictionMarketProvider p) async {
    setState(() => _isLoading = true);
    final payout = await p.claim(widget.event);
    setState(() => _isLoading = false);
    if (payout != null) {
      _snack("+${formatDoro(payout)} réclamés !");
    } else {
      _snack(p.lastError ?? "Échec");
    }
  }

  void _snack(String msg) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtShares(BigInt s) => (s.toDouble() / 1e18).toStringAsFixed(4);
  String _fmtPrice(BigInt p) => (p.toDouble() / 1e18).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PredictionMarketProvider>();
    final w = context.watch<WalletProvider>();
    final myAddress = w.wallets.isNotEmpty ? w.wallets.last.address : "";
    final now = DateTime.now().millisecondsSinceEpoch;

    // Dynamically retrieve the latest state of the event from the provider to show edits/resolutions immediately
    final event = p.openEvents.firstWhere(
      (e) => e.id == widget.event.id,
      orElse: () => p.resolvedEvents.firstWhere(
        (e) => e.id == widget.event.id,
        orElse: () => widget.event,
      ),
    );

    final isOpen = !event.isResolved && now < event.closesAt;

    final orders = p.openShareOrdersFor(event.id);
    final yesPrice = _getYesPrice(event.id, orders);
    final noPrice = 1.0 - yesPrice;

    final posYes = p.positionFor(event.id, yes: true);
    final posNo = p.positionFor(event.id, yes: false);
    final isOracle = event.oracleAddress == myAddress;
    final isCreator = event.creatorId == myAddress;

    final eventPositions = p.node.outcomePositionRepo.positionsForEvent(event.id);
    final totalMinted = eventPositions.fold<BigInt>(BigInt.zero, (s, pos) => s + pos.shares) ~/ BigInt.from(2);
    final totalEscrow = totalMinted * BigInt.from(10).pow(18);

    final outcomeOrders = orders.where((o) => o.outcome == _selectedOutcome && o.isOpen).toList();
    final sells = outcomeOrders.where((o) => o.side == OrderSide.sell).toList()..sort((a, b) => a.pricePerShare.compareTo(b.pricePerShare));
    final buys = outcomeOrders.where((o) => o.side == OrderSide.buy).toList()..sort((a, b) => b.pricePerShare.compareTo(a.pricePerShare));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text("Marché Prédictif", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (isCreator && !event.isResolved)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.muted),
              onSelected: (v) {
                if (v == "edit") _editEvent(p);
                if (v == "delete") _deleteEvent(p);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: "edit", child: Row(children: [
                  Icon(Icons.edit, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text("Modifier"),
                ])),
                PopupMenuItem(value: "delete", child: Row(children: [
                  Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                  SizedBox(width: 8),
                  Text("Supprimer", style: TextStyle(color: AppColors.error)),
                ])),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(event.question,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text, height: 1.3)),
                const SizedBox(height: 12),
                _metaRow(totalEscrow, event.oracleAddress, event.closesAt),
                const SizedBox(height: 20),

                // Probability + Chart Card
                Card(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _probBtn("OUI", yesPrice, Colors.greenAccent)),
                          const SizedBox(width: 12),
                          Expanded(child: _probBtn("NON", noPrice, Colors.redAccent)),
                        ]),
                        const SizedBox(height: 20),
                        const Text("Probabilité OUI", style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 100,
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _ChartPainter(yesPrice),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Oracle panel
                if (isOracle && !event.isResolved) ...[
                  Card(
                    color: Colors.amber.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.gavel, color: Colors.amber, size: 18),
                            SizedBox(width: 8),
                            Text("Oracle", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: FilledButton(onPressed: () => _resolve(p, PredictionOutcome.yes), child: const Text("Trancher OUI"))),
                            const SizedBox(width: 12),
                            Expanded(child: FilledButton(onPressed: () => _resolve(p, PredictionOutcome.no), child: const Text("Trancher NON"))),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Claim panel
                if (event.isResolved) ...[
                  Card(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text("Résolution", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text)),
                          const SizedBox(height: 6),
                          Text("Issue : ${event.winningOutcome == PredictionOutcome.yes ? "OUI" : "NON"}",
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(children: [
                            _posPill("OUI réclamables", posYes.sharesClaimable, Colors.greenAccent),
                            const SizedBox(width: 12),
                            _posPill("NON réclamables", posNo.sharesClaimable, Colors.redAccent),
                          ]),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: ((event.winningOutcome == PredictionOutcome.yes && posYes.sharesClaimable > BigInt.zero) ||
                                      (event.winningOutcome == PredictionOutcome.no && posNo.sharesClaimable > BigInt.zero))
                                  ? () => _claim(p) : null,
                              icon: const Icon(Icons.monetization_on),
                              label: const Text("Réclamer 1 DORO/part"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // My positions
                Card(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Mes Parts", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: _posPill("OUI", posYes.shares, Colors.greenAccent)),
                          const SizedBox(width: 12),
                          Expanded(child: _posPill("NON", posNo.shares, Colors.redAccent)),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Operations
                Card(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Opérations", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                        const SizedBox(height: 16),

                        if (isOpen) ...[
                          const Text("Émettre (Mint)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                          const SizedBox(height: 4),
                          const Text("1 DORO → 1 part OUI + 1 part NON",
                              style: TextStyle(fontSize: 11, color: AppColors.muted)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _mintCtrl,
                                style: const TextStyle(color: AppColors.text),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: "DORO",
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(onPressed: () => _mint(p), child: const Text("Émettre")),
                          ]),
                          const SizedBox(height: 16),
                        ],

                        const Text("Vendre des parts", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                        const SizedBox(height: 4),
                        const Text("Publiez une offre de vente dans le carnet",
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        const SizedBox(height: 8),

                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _orderSharesCtrl,
                              style: const TextStyle(color: AppColors.text),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: "Parts",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _orderPriceCtrl,
                              style: const TextStyle(color: AppColors.text),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: "Prix (DORO)",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(children: [
                            _outcomeChip("OUI", "yes"),
                            const SizedBox(height: 4),
                            _outcomeChip("NON", "no"),
                          ]),
                        ]),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(onPressed: () => _placeOrder(p, myAddress), child: const Text("Publier une Vente")),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Order book
                Card(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text("Carnet d'ordres", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text)),
                          const Spacer(),
                          for (final o in ["yes", "no"])
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text(o == "yes" ? "OUI" : "NON",
                                    style: TextStyle(fontSize: 11, color: _selectedOutcome == o ? Colors.white : AppColors.muted)),
                                selected: _selectedOutcome == o,
                                selectedColor: o == "yes" ? Colors.green : Colors.red,
                                backgroundColor: Colors.white.withValues(alpha: 0.05),
                                onSelected: (v) { if (v) setState(() => _selectedOutcome = o); },
                              ),
                            ),
                        ]),
                        const SizedBox(height: 12),

                        if (sells.isEmpty && buys.isEmpty)
                          const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("Aucun ordre", style: TextStyle(color: AppColors.muted))))
                        else ...[
                          if (sells.isNotEmpty) ...[
                            const Text("VENTES", style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ...sells.map((o) => _orderTile(o, p, myAddress)),
                          ],
                          if (buys.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            const Text("ACHATS", style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                            ...buys.map((o) => _orderTile(o, p, myAddress)),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _orderTile(ShareOrder o, PredictionMarketProvider p, String myAddress) {
    final isMine = o.makerId == myAddress;
    final total = (o.remaining * o.pricePerShare) ~/ BigInt.from(10).pow(18);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text("${_fmtShares(o.remaining)} parts à ${_fmtPrice(o.pricePerShare)} DORO",
          style: const TextStyle(fontSize: 13, color: AppColors.text)),
      subtitle: Text("Total ${formatDoro(total)} — ${_shortId(o.makerId)}",
          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      trailing: isMine
          ? IconButton(icon: const Icon(Icons.cancel, color: AppColors.error),
              onPressed: () => p.cancelShareOrder(o.id))
          : FilledButton(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: o.side == OrderSide.sell ? () => _fillOrder(p, o) : null,
              child: const Text("Acheter", style: TextStyle(fontSize: 11))),
    );
  }

  Widget _outcomeChip(String label, String value) {
    final sel = _selectedOutcome == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedOutcome = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? (value == "yes" ? Colors.green : Colors.red) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? Colors.white : AppColors.muted)),
      ),
    );
  }

  Widget _probBtn(String label, double prob, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        const SizedBox(height: 2),
        Text("${(prob * 100).toStringAsFixed(1)}%", style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 20)),
      ]),
    );
  }

  Widget _posPill(String label, BigInt shares, Color c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 2),
        Text(_fmtShares(shares), style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 14)),
      ]),
    );
  }

  Widget _metaRow(BigInt escrow, String oracle, int closesAt) {
    return Wrap(spacing: 8, runSpacing: 4, children: [
      _chip(Icons.monetization_on, "Escrow ${formatDoro(escrow)}"),
      _chip(Icons.person, _shortId(oracle)),
      _chip(Icons.timer, _fmtDate(DateTime.fromMillisecondsSinceEpoch(closesAt))),
    ]);
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final double yesPrice;
  _ChartPainter(this.yesPrice);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height * (1.0 - yesPrice);
    final line = Paint()..color = Colors.greenAccent..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), line);
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.greenAccent.withValues(alpha: 0.15), Colors.greenAccent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final path = Path()
      ..moveTo(0, mid)
      ..lineTo(size.width, mid)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.yesPrice != yesPrice;
}
