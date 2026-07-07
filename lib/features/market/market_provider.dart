// lib/features/market/market_provider.dart
import 'package:flutter/material.dart';
import '../../core/market/order_model.dart';
import '../../core/market/trade_model.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/storage/secure/keypair_store.dart';
import '../wallet/wallet_provider.dart';

class MarketProvider extends ChangeNotifier {
  final P2PNode node;
  WalletProvider? walletProvider;
  String? lastError;

  MarketProvider(this.node, {this.walletProvider}) {
    node.marketKernel.orderBookChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    node.marketKernel.tradeUpdates.listen((_) {
      if (hasListeners) notifyListeners();
    });
  }

  List<Order> get sellOrders => node.orderRepo.openSells();
  List<Order> get buyOrders => node.orderRepo.openBuys();
  List<Trade> get tradeHistory => node.tradeRepo.confirmedHistory();

  /// Trades où JE suis vendeur et dois confirmer/refuser — que ce soit
  /// parce que j'avais publié l'offre de vente, ou parce que j'ai
  /// proposé de vendre à une demande d'un autre.
  List<Trade> get myPendingSales =>
      node.tradeRepo.all().where((t) => t.sellerId == node.nodeId && t.status == TradeStatus.pending).toList();

  /// Trades où je suis acheteur, en attente que le vendeur confirme.
  List<Trade> get myPendingPurchases =>
      node.tradeRepo.all().where((t) => t.buyerId == node.nodeId && t.status == TradeStatus.pending).toList();

  /// Dernier prix réellement échangé — jamais une valeur inventée.
  BigInt? get lastPrice => tradeHistory.isNotEmpty ? tradeHistory.last.pricePerUnit : null;
  BigInt? get bestAsk => sellOrders.isNotEmpty ? sellOrders.first.pricePerUnit : null;
  BigInt? get bestBid => buyOrders.isNotEmpty ? buyOrders.first.pricePerUnit : null;

  Future<Order?> publishOrder({
    required OrderSide side,
    required BigInt amount,
    required BigInt pricePerUnit,
    String currency = "USD",
  }) async {
    if (walletProvider == null || walletProvider!.wallets.isEmpty) {
      lastError = "Crée un wallet avant de publier un ordre.";
      notifyListeners();
      return null;
    }
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable pour ce wallet.";
      notifyListeners();
      return null;
    }
    if (side == OrderSide.sell && wallet.balance < amount) {
      lastError = "Solde insuffisant pour vendre cette quantité.";
      notifyListeners();
      return null;
    }
    final order = await node.marketKernel.createAndPublishOrder(
      side: side, amount: amount, pricePerUnit: pricePerUnit, currency: currency, keyPair: keyPair,
    );
    notifyListeners();
    return order;
  }

  Future<void> cancelOrder(Order order) async {
    final keyPair = await KeypairStore.load(order.makerId);
    if (keyPair == null) return;
    await node.marketKernel.cancelOrder(order.id, keyPair);
    notifyListeners();
  }

  Future<void> requestTrade(Order order, {BigInt? amount}) async {
    await node.marketKernel.sendTradeRequest(order: order, amount: amount ?? order.amount, myId: node.nodeId);
    notifyListeners();
  }

  /// Déclenche le VRAI transfert DORO signé, puis notifie l'acheteur.
  /// À n'appeler qu'après avoir reçu le paiement hors-app.
  Future<bool> confirmSale(Trade trade) async {
    if (walletProvider == null) return false;
    if (trade.sellerId != node.nodeId) {
      lastError = "Seul le vendeur peut confirmer ce trade.";
      notifyListeners();
      return false;
    }
    final txId = await walletProvider!.send(from: trade.sellerId, to: trade.buyerId, amount: trade.amount);
    if (txId == null) {
      lastError = "Le transfert DORO a échoué (solde ou clé locale manquante).";
      notifyListeners();
      return false;
    }
    await node.marketKernel.acceptTrade(trade, txId);
    notifyListeners();
    return true;
  }

  Future<void> rejectTrade(Trade trade) async {
    await node.marketKernel.rejectTrade(trade);
    notifyListeners();
  }
}