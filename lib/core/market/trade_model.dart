// lib/core/market/trade_model.dart
enum TradeStatus { pending, confirmed, rejected }

/// Une négociation privée 1:1 entre deux pairs autour d'un Order.
/// sellerId = celui qui détient et envoie les DORO. buyerId = celui qui
/// les reçoit. Le statut passe à `confirmed` seulement après un vrai
/// transfert DORO on-chain (voir MarketProvider.confirmSale).
class Trade {
  final String id;
  final String orderId;
  final String sellerId;
  final String buyerId;
  final BigInt amount;
  final BigInt pricePerUnit;
  final String currency;
  final int timestamp;
  final TradeStatus status;
  final String? txId;

  Trade({
    required this.id,
    required this.orderId,
    required this.sellerId,
    required this.buyerId,
    required this.amount,
    required this.pricePerUnit,
    required this.currency,
    required this.timestamp,
    required this.status,
    this.txId,
  });

  Trade copyWith({TradeStatus? status, String? txId}) => Trade(
        id: id, orderId: orderId, sellerId: sellerId, buyerId: buyerId,
        amount: amount, pricePerUnit: pricePerUnit, currency: currency,
        timestamp: timestamp, status: status ?? this.status, txId: txId ?? this.txId,
      );

  Map<String, dynamic> toJson() => {
        "id": id, "orderId": orderId, "sellerId": sellerId, "buyerId": buyerId,
        "amount": amount.toString(), "pricePerUnit": pricePerUnit.toString(),
        "currency": currency, "timestamp": timestamp, "status": status.name, "txId": txId,
      };

  factory Trade.fromJson(Map<String, dynamic> json) => Trade(
        id: json["id"] as String,
        orderId: json["orderId"] as String,
        sellerId: json["sellerId"] as String,
        buyerId: json["buyerId"] as String,
        amount: BigInt.parse(json["amount"] as String),
        pricePerUnit: BigInt.parse(json["pricePerUnit"] as String),
        currency: json["currency"] as String? ?? "USD",
        timestamp: json["timestamp"] as int,
        status: TradeStatus.values.firstWhere((s) => s.name == json["status"], orElse: () => TradeStatus.pending),
        txId: json["txId"] as String?,
      );
}