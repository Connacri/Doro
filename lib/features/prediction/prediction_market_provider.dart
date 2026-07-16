// lib/features/prediction/prediction_market_provider.dart
import 'package:flutter/material.dart';
import '../../core/p2p/p2p_node.dart';
import '../../core/prediction/outcome_position.dart';
import '../../core/prediction/prediction_event.dart';
import '../../core/prediction/profit_calculator.dart';
import '../../core/prediction/share_order.dart';
import '../../core/market/order_model.dart' show OrderSide;
import '../../core/storage/secure/keypair_store.dart';
import '../wallet/wallet_provider.dart';

class PredictionMarketProvider extends ChangeNotifier {
  final P2PNode node;
  WalletProvider? walletProvider;
  String? lastError;

  PredictionMarketProvider(this.node, {this.walletProvider}) {
    node.predictionKernel.eventChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    node.predictionKernel.positionChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    node.predictionKernel.orderChanges.listen((_) {
      if (hasListeners) notifyListeners();
    });
    // Listen to market kernel trade updates to refresh positions
    node.marketKernel.tradeUpdates.listen((_) {
      if (hasListeners) notifyListeners();
    });
  }

  List<PredictionEvent> get openEvents => node.predictionEventRepo.openEvents();
  List<PredictionEvent> get resolvedEvents => node.predictionEventRepo.resolvedEvents();

  List<ShareOrder> openShareOrdersFor(String eventId) =>
      node.shareOrderRepo.openOrdersForEvent(eventId);

  OutcomePosition positionFor(String eventId, {required bool yes}) {
    final holder = walletProvider?.wallets.isNotEmpty == true ? walletProvider!.wallets.last.address : "";
    return node.outcomePositionRepo.get(eventId, yes ? "yes" : "no", holder);
  }

  /// Crée un nouvel événement de pari — l'utilisateur courant en devient
  /// l'oracle (résolveur) par défaut ; passez `oracleAddress`/
  /// `oraclePublicKey` pour désigner un tiers.
  Future<PredictionEvent?> createEvent({
    required String question,
    required Duration opensFor,
    String? oracleAddress,
    String? oraclePublicKey,
  }) async {
    if (!_ensureWallet()) return null;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable pour ce wallet.";
      notifyListeners();
      return null;
    }
    final event = await node.predictionKernel.createAndPublishEvent(
      question: question,
      oracleAddress: oracleAddress ?? wallet.address,
      oraclePublicKey: oraclePublicKey ?? wallet.publicKey,
      opensFor: opensFor,
      creatorKeyPair: keyPair,
    );
    notifyListeners();
    return event;
  }

  /// Dépose `shares` DORO en escrow et reçoit `shares` parts OUI + `shares`
  /// parts NON (1 DORO = 1 part complète, comme dans l'exemple de la Fed).
  Future<bool> buyCompleteSet({required PredictionEvent event, required BigInt shares}) async {
    if (!_ensureWallet()) return false;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable pour ce wallet.";
      notifyListeners();
      return false;
    }
    final txId = await node.predictionKernel.mintCompleteSet(
      event: event, shares: shares,
      holderAddress: wallet.address, holderPublicKeyHex: wallet.publicKey, holderKeyPair: keyPair,
    );
    if (txId == null) {
      lastError = "Émission refusée (solde insuffisant ou marché fermé).";
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> deleteEvent(PredictionEvent event) async {
    if (!_ensureWallet()) return false;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable.";
      notifyListeners();
      return false;
    }
    if (wallet.address != event.creatorId) {
      lastError = "Seul le créateur peut supprimer ce marché.";
      notifyListeners();
      return false;
    }
    await node.predictionKernel.deleteEvent(event);
    notifyListeners();
    return true;
  }

  Future<bool> resolve({required PredictionEvent event, required PredictionOutcome outcome}) async {
    if (!_ensureWallet()) return false;
    final wallet = walletProvider!.wallets.last;
    if (wallet.address != event.oracleAddress) {
      lastError = "Seul l'oracle désigné peut résoudre ce marché.";
      notifyListeners();
      return false;
    }
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) return false;
    await node.predictionKernel.resolveEvent(event: event, outcome: outcome, oracleKeyPair: keyPair);
    notifyListeners();
    return true;
  }

  /// Réclame le paiement des parts gagnantes détenues — crédite
  /// directement le solde DORO du wallet courant.
  Future<BigInt?> claim(PredictionEvent event) async {
    if (!_ensureWallet()) return null;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) return null;
    final payout = await node.predictionKernel.claimPayout(
      event: event, holderAddress: wallet.address, holderKeyPair: keyPair,
    );
    if (payout == null) {
      lastError = "Rien à réclamer sur ce marché.";
    } else {
      // Reflète le crédit protocolaire (déjà appliqué dans dag.balances)
      // dans le cache local WalletCore/UI.
      walletProvider!.core.creditIfLocal(wallet.address, payout);
      await walletProvider!.repo.syncFromCore(walletProvider!.core);
    }
    notifyListeners();
    return payout;
  }

  /// Profit net (unités atomiques DORO) sur la position OUI ou NON
  /// détenue, une fois l'issue connue — exactement la formule demandée :
  /// (1 - prix d'achat) × contrats si gagné, -prix d'achat × contrats sinon.
  BigInt? projectedProfit({
    required PredictionEvent event,
    required bool yes,
    required BigInt averagePurchasePricePerShare,
  }) {
    if (!event.isResolved) return null;
    final won = (event.winningOutcome == PredictionOutcome.yes) == yes;
    final position = positionFor(event.id, yes: yes);
    return ProfitCalculator.totalProfit(
      purchasePricePerShare: averagePurchasePricePerShare,
      shares: position.shares,
      outcomeWon: won,
    );
  }

  bool _ensureWallet() {
    if (walletProvider == null || walletProvider!.wallets.isEmpty) {
      lastError = "Crée un wallet avant de parier.";
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<ShareOrder?> publishShareOrder({
    required String eventId,
    required String outcome,
    required OrderSide side,
    required BigInt shares,
    required BigInt pricePerShare,
  }) async {
    if (!_ensureWallet()) return null;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) {
      lastError = "Clé privée locale introuvable.";
      notifyListeners();
      return null;
    }
    final order = await node.predictionKernel.createAndPublishShareOrder(
      eventId: eventId,
      outcome: outcome,
      makerId: wallet.address,
      makerPublicKeyHex: wallet.publicKey,
      side: side,
      shares: shares,
      pricePerShare: pricePerShare,
      makerKeyPair: keyPair,
    );
    notifyListeners();
    return order;
  }

  Future<bool> cancelShareOrder(String orderId) async {
    if (!_ensureWallet()) return false;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) return false;
    final ok = await node.predictionKernel.cancelShareOrder(
      orderId: orderId,
      makerKeyPair: keyPair,
    );
    notifyListeners();
    return ok;
  }

  Future<String?> fillShareOrder({
    required ShareOrder order,
    required BigInt sharesToFill,
  }) async {
    if (!_ensureWallet()) return null;
    final wallet = walletProvider!.wallets.last;
    final keyPair = await KeypairStore.load(wallet.address);
    if (keyPair == null) return null;
    final txId = await node.predictionKernel.fillShareOrder(
      order: order,
      sharesToFill: sharesToFill,
      buyerAddress: wallet.address,
      buyerPublicKeyHex: wallet.publicKey,
      buyerKeyPair: keyPair,
    );
    if (txId != null) {
      walletProvider!.core.creditIfLocal(wallet.address, BigInt.zero);
      await walletProvider!.repo.syncFromCore(walletProvider!.core);
    }
    notifyListeners();
    return txId;
  }
}
