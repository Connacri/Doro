// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/market/order_model.dart';
import '../../core/market/trade_model.dart';
import '../market/market_provider.dart';
import '../wallet/wallet_provider.dart';
import '../wallet/wallet_screen.dart' show formatDoro;

String _fmtPrice(BigInt cents) => "\$${(cents.toDouble() / 100).toStringAsFixed(2)}";
String _shortId(String id) => id.length > 14 ? "${id.substring(0, 8)}…${id.substring(id.length - 4)}" : id;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openCreateOrder(BuildContext context, OrderSide side) {
    final amountCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(side == OrderSide.sell ? "Vendre des DORO" : "Publier une demande d'achat",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: "Quantité (DORO)"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: "Prix par DORO (USD)"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final amountStr = amountCtrl.text.trim();
                final priceStr = priceCtrl.text.trim();
                if (amountStr.isEmpty || priceStr.isEmpty) return;
                final amount = BigInt.from(double.parse(amountStr) * 1e18);
                final price = BigInt.from((double.parse(priceStr) * 100).round());
                final market = context.read<MarketProvider>();
                final navigator = Navigator.of(ctx);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final order = await market.publishOrder(side: side, amount: amount, pricePerUnit: price);
                navigator.pop();
                scaffoldMessenger.showSnackBar(SnackBar(
                  content: Text(order != null ? "Ordre publié" : (market.lastError ?? "Échec")),
                ));
              },
              child: const Text("Publier"),
            ),
          ],
        ),
      ),
    );
  }

  void _requestTrade(BuildContext context, Order order) {
    final isSell = order.side == OrderSide.sell;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSell ? "Acheter à ${_shortId(order.makerId)}" : "Vendre à ${_shortId(order.makerId)}"),
        content: Text(
          "${formatDoro(order.amount)} à ${_fmtPrice(order.pricePerUnit)}/DORO.\n\n"
          "Le règlement en USD se fait hors application. ${isSell ? 'Le vendeur' : 'Toi'} "
          "libérera les DORO seulement après réception du paiement.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            onPressed: () async {
              final market = context.read<MarketProvider>();
              final navigator = Navigator.of(ctx);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              await market.requestTrade(order);
              navigator.pop();
              scaffoldMessenger.showSnackBar(const SnackBar(content: Text("Proposition envoyée")));
            },
            child: const Text("Confirmer la proposition"),
          ),
        ],
      ),
    );
  }

  void _reviewPendingSale(BuildContext context, Trade trade) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer la vente"),
        content: Text(
          "${formatDoro(trade.amount)} → ${_shortId(trade.buyerId)}\n"
          "Prix convenu : ${_fmtPrice(trade.pricePerUnit)}/DORO.\n\n"
          "Confirme SEULEMENT si tu as déjà reçu le paiement hors-app. "
          "Ça enverra réellement les DORO, aucune annulation possible ensuite.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<MarketProvider>().rejectTrade(trade);
              Navigator.pop(ctx);
            },
            child: const Text("Refuser"),
          ),
          FilledButton(
            onPressed: () async {
              final market = context.read<MarketProvider>();
              final navigator = Navigator.of(ctx);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final ok = await market.confirmSale(trade);
              navigator.pop();
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text(ok ? "DORO envoyés" : (market.lastError ?? "Échec"))),
              );
            },
            child: const Text("J'ai été payé — envoyer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final market = context.watch<MarketProvider>();
    final balance = wallet.wallets.isNotEmpty ? wallet.wallets.first.balance : BigInt.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Doro"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Achat: ${market.bestBid != null ? _fmtPrice(market.bestBid!) : '—'}",
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                const SizedBox(width: 16),
                Text("Vente: ${market.bestAsk != null ? _fmtPrice(market.bestAsk!) : '—'}",
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Solde total", style: TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    Text(formatDoro(balance), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    if (market.lastPrice != null) ...[
                      const SizedBox(height: 4),
                      Text("Dernier prix échangé : ${_fmtPrice(market.lastPrice!)}/DORO",
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.sell),
                    label: const Text("Vendre"),
                    onPressed: () => _openCreateOrder(context, OrderSide.sell),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.shopping_cart),
                    label: const Text("Acheter"),
                    onPressed: () => _openCreateOrder(context, OrderSide.buy),
                  ),
                ),
              ],
            ),
            if (market.tradeHistory.length >= 2) ...[
              const SizedBox(height: 24),
              const Text("Historique des prix", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(
                  painter: _PriceChartPainter(
                    market.tradeHistory.map((t) => t.pricePerUnit.toDouble() / 100).toList(),
                  ),
                ),
              ),
            ],
            if (market.myPendingSales.isNotEmpty || market.myPendingPurchases.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text("Transactions en attente", style: TextStyle(fontWeight: FontWeight.bold)),
              ...market.myPendingSales.map((t) => Card(
                    color: Colors.amber.shade900.withValues(alpha: 0.3),
                    child: ListTile(
                      title: Text("Vendre ${formatDoro(t.amount)} à ${_shortId(t.buyerId)}"),
                      subtitle: Text("${_fmtPrice(t.pricePerUnit)}/DORO — en attente de ta confirmation"),
                      trailing: FilledButton(onPressed: () => _reviewPendingSale(context, t), child: const Text("Traiter")),
                    ),
                  )),
              ...market.myPendingPurchases.map((t) => Card(
                    child: ListTile(
                      title: Text("Achat de ${formatDoro(t.amount)} auprès de ${_shortId(t.sellerId)}"),
                      subtitle: Text("${_fmtPrice(t.pricePerUnit)}/DORO — en attente que le vendeur confirme"),
                      trailing: TextButton(
                        onPressed: () => context.read<MarketProvider>().rejectTrade(t),
                        child: const Text("Annuler"),
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 24),
            const Text("Offres de vente", style: TextStyle(fontWeight: FontWeight.bold)),
            if (market.sellOrders.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text("Aucune offre pour l'instant."))
            else
              ...market.sellOrders.map((o) => ListTile(
                    leading: const Icon(Icons.sell, color: Colors.redAccent),
                    title: Text("${formatDoro(o.amount)} à ${_fmtPrice(o.pricePerUnit)}/DORO"),
                    subtitle: Text("Vendeur : ${_shortId(o.makerId)}", style: const TextStyle(fontSize: 11)),
                    trailing: o.makerId == (wallet.wallets.isNotEmpty ? wallet.wallets.first.address : "")
                        ? IconButton(icon: const Icon(Icons.cancel), onPressed: () => market.cancelOrder(o))
                        : FilledButton(onPressed: () => _requestTrade(context, o), child: const Text("Acheter")),
                  )),
            const SizedBox(height: 16),
            const Text("Demandes d'achat", style: TextStyle(fontWeight: FontWeight.bold)),
            if (market.buyOrders.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text("Aucune demande pour l'instant."))
            else
              ...market.buyOrders.map((o) => ListTile(
                    leading: const Icon(Icons.shopping_cart, color: Colors.greenAccent),
                    title: Text("${formatDoro(o.amount)} à ${_fmtPrice(o.pricePerUnit)}/DORO"),
                    subtitle: Text("Acheteur : ${_shortId(o.makerId)}", style: const TextStyle(fontSize: 11)),
                    trailing: o.makerId == (wallet.wallets.isNotEmpty ? wallet.wallets.first.address : "")
                        ? IconButton(icon: const Icon(Icons.cancel), onPressed: () => market.cancelOrder(o))
                        : FilledButton(onPressed: () => _requestTrade(context, o), child: const Text("Vendre")),
                  )),
          ],
        ),
      ),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  final List<double> prices;
  _PriceChartPainter(this.prices);

  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;
    final minP = prices.reduce((a, b) => a < b ? a : b);
    final maxP = prices.reduce((a, b) => a > b ? a : b);
    final range = (maxP - minP).abs() < 1e-9 ? 1.0 : (maxP - minP);

    final path = Path();
    for (var i = 0; i < prices.length; i++) {
      final x = size.width * i / (prices.length - 1);
      final y = size.height - ((prices[i] - minP) / range) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(path, Paint()..color = Colors.greenAccent..strokeWidth = 2..style = PaintingStyle.stroke);

    final fillPath = Path.from(path)..lineTo(size.width, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(fillPath, Paint()..color = Colors.greenAccent.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) => oldDelegate.prices != prices;
}