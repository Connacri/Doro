// lib/core/kernels/market/market_kernel.dart
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../../crypto/signature.dart';
import '../../dag/dag_engine.dart';
import '../../market/order_model.dart';
import '../../market/trade_model.dart';
import '../../p2p/webrtc_engine.dart';
import '../../storage/repositories/order_repository.dart';
import '../../storage/repositories/trade_repository.dart';
import '../../utils/id_generator.dart';
import '../../utils/node_identity.dart';
import '../../utils/logger.dart';
import '../../wallet/address_generator.dart';

class MarketKernel {
  final NodeIdentityKeyPair identity;
  final WebRTCNetworkEngine p2p;
  final OrderRepository orderRepo;
  final TradeRepository tradeRepo;

  /// Nécessaire pour vérifier qu'un `trade_accept` correspond à un VRAI
  /// paiement DORO déjà finalisé — sans ça, n'importe quel pair pouvait
  /// prétendre avoir payé (txId inventé) et se faire créditer un ordre
  /// "filled" sans jamais avoir transféré le moindre token.
  final DagEngine dag;

  final CryptoService _crypto = CryptoService();

  final Set<String> _seenOrders = {};
  final Set<String> _seenOrderCancels = {};
  final Set<String> _seenTradeEvents = {};

  final _orderBookChanges = StreamController<void>.broadcast();
  Stream<void> get orderBookChanges => _orderBookChanges.stream;
  final _tradeUpdates = StreamController<void>.broadcast();
  Stream<void> get tradeUpdates => _tradeUpdates.stream;

  MarketKernel({
    required this.identity,
    required this.p2p,
    required this.orderRepo,
    required this.tradeRepo,
    required this.dag,
  }) {
    p2p.messages.listen((msg) {
      final data = msg.data;
      if (data is! Map<String, dynamic>) return;
      switch (data["type"]) {
        case "order_publish": _handleOrderPublish(data); break;
        case "order_cancel": _handleOrderCancel(data); break;
        case "trade_request": _handleTradeRequest(data); break;
        case "trade_accept": _handleTradeEvent(data); break;
        case "trade_reject": _handleTradeEvent(data); break;
      }
    });
  }

  Future<Order> createAndPublishOrder({
    required OrderSide side,
    required BigInt amount,
    required BigInt pricePerUnit,
    required String currency,
    required KeyPair keyPair,
  }) async {
    final unsigned = Order(
      id: IdGenerator.generateId("order"), makerId: identity.nodeId, makerPublicKey: identity.publicKeyHex,
      side: side, amount: amount, pricePerUnit: pricePerUnit, currency: currency,
      timestamp: DateTime.now().millisecondsSinceEpoch, signature: "",
    );
    final sig = await _crypto.sign(utf8.encode(unsigned.hash), keyPair: keyPair);
    final order = Order(
      id: unsigned.id, makerId: unsigned.makerId, makerPublicKey: unsigned.makerPublicKey,
      side: unsigned.side, amount: unsigned.amount, pricePerUnit: unsigned.pricePerUnit,
      currency: unsigned.currency, timestamp: unsigned.timestamp, signature: _bytesToHex(sig.bytes),
    );

    _seenOrders.add(order.id);
    orderRepo.save(order);
    p2p.broadcast({"type": "order_publish", ...order.toJson()});
    _orderBookChanges.add(null);
    return order;
  }

  Future<void> cancelOrder(String orderId, KeyPair keyPair) async {
    final sig = await _crypto.sign(utf8.encode("cancel:$orderId:${identity.nodeId}"), keyPair: keyPair);
    _seenOrderCancels.add(orderId);
    orderRepo.markCancelled(orderId);
    p2p.broadcast({
      "type": "order_cancel", "orderId": orderId, "makerId": identity.nodeId,
      "makerPublicKey": identity.publicKeyHex, "signature": _bytesToHex(sig.bytes),
    });
    _orderBookChanges.add(null);
  }

  Future<void> _handleOrderPublish(Map<String, dynamic> data) async {
    late final Order order;
    try {
      order = Order.fromJson(data);
    } catch (e) {
      Logger.warn("Ordre malformé ignoré : $e");
      return;
    }
    if (_seenOrders.contains(order.id) || orderRepo.exists(order.id)) return;
    if (AddressGenerator.generate(order.makerPublicKey) != order.makerId) {
      Logger.warn("Ordre ${order.id} rejeté : makerId incohérent avec la clé publique");
      return;
    }
    if (!await _verify(order.hash, order.makerPublicKey, order.signature)) {
      Logger.warn("Ordre ${order.id} rejeté : signature invalide");
      return;
    }
    if (order.amount <= BigInt.zero || order.pricePerUnit <= BigInt.zero) return;

    _seenOrders.add(order.id);
    orderRepo.save(order);
    p2p.broadcast(data);
    _orderBookChanges.add(null);
  }

  Future<void> _handleOrderCancel(Map<String, dynamic> data) async {
    final orderId = data["orderId"] as String?;
    final makerId = data["makerId"] as String?;
    final makerPublicKey = data["makerPublicKey"] as String?;
    final signature = data["signature"] as String?;
    if (orderId == null || makerId == null || makerPublicKey == null || signature == null) return;
    if (_seenOrderCancels.contains(orderId)) return;
    if (AddressGenerator.generate(makerPublicKey) != makerId) return;
    if (!await _verify("cancel:$orderId:$makerId", makerPublicKey, signature)) return;

    _seenOrderCancels.add(orderId);
    orderRepo.markCancelled(orderId);
    p2p.broadcast(data);
    _orderBookChanges.add(null);
  }

  /// Proposition privée envoyée au créateur de l'ordre — jamais diffusée
  /// au reste du réseau. Fonctionne symétriquement pour les deux sens :
  /// acheter une offre de vente, ou proposer de vendre à une demande.
  Future<Trade> sendTradeRequest({required Order order, required BigInt amount, required String myId}) async {
    final iAmBuyer = order.side == OrderSide.sell; // j'achète son offre de vente
    final trade = Trade(
      id: IdGenerator.generateId("trade"),
      orderId: order.id,
      sellerId: iAmBuyer ? order.makerId : myId,
      buyerId: iAmBuyer ? myId : order.makerId,
      amount: amount,
      pricePerUnit: order.pricePerUnit,
      currency: order.currency,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: TradeStatus.pending,
    );
    tradeRepo.save(trade);
    _seenTradeEvents.add(trade.id);
    p2p.sendToPeer(order.makerId, {"type": "trade_request", ...trade.toJson()});
    _tradeUpdates.add(null);
    return trade;
  }

  void _handleTradeRequest(Map<String, dynamic> data) {
    late final Trade trade;
    try {
      trade = Trade.fromJson(data);
    } catch (e) {
      return;
    }
    if (_seenTradeEvents.contains(trade.id)) return;
    _seenTradeEvents.add(trade.id);
    tradeRepo.save(trade);
    _tradeUpdates.add(null);
  }

  /// À appeler UNIQUEMENT après un vrai transfert DORO on-chain déjà
  /// effectué (voir MarketProvider.confirmSale) — txId en est la preuve.
  /// Le message envoyé est signé : le récepteur vérifie cette signature
  /// ET que `txId` correspond réellement à un paiement finalisé sur le
  /// DAG avant d'accepter la confirmation (voir `_handleTradeEvent`).
  Future<void> acceptTrade(Trade trade, String txId) async {
    final confirmed = trade.copyWith(status: TradeStatus.confirmed, txId: txId);
    tradeRepo.save(confirmed);
    orderRepo.markFilled(trade.orderId);
    final counterpart = confirmed.sellerId == identity.nodeId ? confirmed.buyerId : confirmed.sellerId;
    final payload = await _signedTradeEvent("trade_accept", confirmed);
    if (confirmed.currency.startsWith("EVENT:")) {
      p2p.broadcast(payload);
    } else {
      p2p.sendToPeer(counterpart, payload);
    }
    _tradeUpdates.add(null);
    _orderBookChanges.add(null);
  }

  Future<void> rejectTrade(Trade trade) async {
    final rejected = trade.copyWith(status: TradeStatus.rejected);
    tradeRepo.save(rejected);
    final counterpart = rejected.sellerId == identity.nodeId ? rejected.buyerId : rejected.sellerId;
    final payload = await _signedTradeEvent("trade_reject", rejected);
    p2p.sendToPeer(counterpart, payload);
    _tradeUpdates.add(null);
  }

  Future<Map<String, dynamic>> _signedTradeEvent(String type, Trade trade) async {
    final message = "${trade.id}:${trade.status.name}:${trade.txId ?? ''}";
    final sig = await _crypto.sign(utf8.encode(message), keyPair: identity.keyPair);
    return {
      "type": type,
      ...trade.toJson(),
      "signerPublicKey": identity.publicKeyHex,
      "signature": _bytesToHex(sig.bytes),
    };
  }

  Future<void> _handleTradeEvent(Map<String, dynamic> data) async {
    late final Trade trade;
    try {
      trade = Trade.fromJson(data);
    } catch (_) {
      return;
    }

    final signerPublicKey = data["signerPublicKey"] as String?;
    final signature = data["signature"] as String?;
    if (signerPublicKey == null || signature == null) {
      Logger.warn("Événement de trade ${trade.id} rejeté : non signé");
      return;
    }

    // Le signataire doit être L'AUTRE partie du trade — pas moi-même,
    // pas un tiers qui n'a rien à voir avec cette négociation.
    final signerAddress = AddressGenerator.generate(signerPublicKey);
    final expectedCounterpart =
        trade.sellerId == identity.nodeId ? trade.buyerId : trade.sellerId;
    if (signerAddress != expectedCounterpart) {
      Logger.warn("Événement de trade ${trade.id} rejeté : signataire ($signerAddress) "
          "n'est pas la contrepartie attendue ($expectedCounterpart)");
      return;
    }

    final message = "${trade.id}:${trade.status.name}:${trade.txId ?? ''}";
    if (!await _verify(message, signerPublicKey, signature)) {
      Logger.warn("Événement de trade ${trade.id} rejeté : signature invalide");
      return;
    }

    // Preuve de paiement on-chain OBLIGATOIRE avant d'accepter une
    // confirmation — sans ce contrôle, n'importe qui pouvait envoyer un
    // txId inventé et se faire créditer un ordre "filled" sans avoir
    // jamais transféré le moindre DORO.
    if (trade.status == TradeStatus.confirmed) {
      final txId = trade.txId;
      if (txId == null || !_paymentProven(trade, txId)) {
        Logger.warn("Trade ${trade.id} rejeté : txId '$txId' ne prouve pas le paiement on-chain");
        return;
      }
    }

    // Pas besoin de déduplication ici : `tradeRepo.save()` fait un upsert
    // par `tradeId`, donc recevoir deux fois le même événement (déjà
    // vérifié ci-dessus) est inoffensif — la seconde écriture donne le
    // même état final.
    tradeRepo.save(trade);
    _tradeUpdates.add(null);
    _orderBookChanges.add(null);
  }

  /// Vérifie que `txId` référence une transaction RÉELLEMENT acceptée
  /// dans MON PROPRE DAG (donc déjà passée par la validation complète —
  /// structure, signature, solde, nonce — de `DagEngine.addValidated`),
  /// correctement dirigée (du vendeur vers l'acheteur) et d'un montant
  /// suffisant. On n'exige pas ici la finalité multi-pairs complète : sur
  /// un petit réseau (juste vendeur + acheteur), le nombre de confirmeurs
  /// distincts nécessaire par défaut (2) ne serait jamais atteignable et
  /// bloquerait indéfiniment des trades pourtant légitimes. La présence
  /// dans le ledger local suffit déjà à exclure un txId inventé.
  bool _paymentProven(Trade trade, String txId) {
    final tx = dag.ledger[txId];
    if (tx == null) return false;
    if (tx.from != trade.sellerId) return false;
    if (tx.to != trade.buyerId) return false;
    if (tx.amount < trade.amount) return false;
    return true;
  }

  Future<bool> _verify(String message, String publicKeyHex, String signatureHex) async {
    try {
      final publicKey = SimplePublicKey(_hexToBytes(publicKeyHex), type: KeyPairType.ed25519);
      final signature = Signature(_hexToBytes(signatureHex), publicKey: publicKey);
      return await _crypto.verify(utf8.encode(message), signature: signature);
    } catch (e) {
      return false;
    }
  }

  String _bytesToHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  void dispose() {
    _orderBookChanges.close();
    _tradeUpdates.close();
  }
}