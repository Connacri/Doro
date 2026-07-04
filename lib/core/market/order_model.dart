// lib/core/market/order_model.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

enum OrderSide { sell, buy }

/// Un ordre du carnet — offre de vente ("sell") ou demande d'achat ("buy").
/// Signé par son créateur, diffusé en flood-gossip comme une transaction.
class Order {
  final String id;
  final String makerId; // adresse = clé publique du créateur
  final String makerPublicKey;
  final OrderSide side;
  final BigInt amount; // quantité de DORO, unité atomique (18 décimales)
  final BigInt pricePerUnit; // prix par DORO, en centimes de `currency`
  final String currency; // référence d'affichage, pas un rail de paiement intégré
  final int timestamp;
  final String signature;

  Order({
    required this.id,
    required this.makerId,
    required this.makerPublicKey,
    required this.side,
    required this.amount,
    required this.pricePerUnit,
    required this.currency,
    required this.timestamp,
    required this.signature,
  });

  String get hash {
    final raw = [id, makerId, side.name, amount.toString(), pricePerUnit.toString(), currency, timestamp.toString()].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "makerId": makerId,
        "makerPublicKey": makerPublicKey,
        "side": side.name,
        "amount": amount.toString(),
        "pricePerUnit": pricePerUnit.toString(),
        "currency": currency,
        "timestamp": timestamp,
        "signature": signature,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json["id"] as String,
        makerId: json["makerId"] as String,
        makerPublicKey: json["makerPublicKey"] as String,
        side: (json["side"] as String) == "buy" ? OrderSide.buy : OrderSide.sell,
        amount: BigInt.parse(json["amount"] as String),
        pricePerUnit: BigInt.parse(json["pricePerUnit"] as String),
        currency: json["currency"] as String? ?? "USD",
        timestamp: json["timestamp"] as int,
        signature: json["signature"] as String? ?? "",
      );
}