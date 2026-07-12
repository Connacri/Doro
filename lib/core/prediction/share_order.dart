// lib/core/prediction/share_order.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import '../market/order_model.dart' show OrderSide;

/// Un ordre du carnet SPÉCIFIQUE aux parts d'un événement de pari — même
/// esprit que `Order` (carnet OTC DORO/fiat) mais pour un actif différent
/// (des parts OUI/NON) et avec un règlement 100% on-chain et automatique
/// (pas de confirmation manuelle du vendeur nécessaire) — voir
/// `PredictionMarketKernel.fillSellOrder` : puisque les DEUX jambes de
/// l'échange (le paiement DORO et le transfert de parts) sont vérifiables
/// objectivement dans l'état local de chaque pair, aucune confiance n'est
/// nécessaire entre les deux parties, contrairement au carnet DORO/fiat
/// où le paiement fiat ne peut jamais être prouvé on-chain.
///
/// Limite assumée en v1 : seuls les ordres `sell` (le maker détient déjà
/// les parts et les propose à la vente) sont exécutables automatiquement
/// par un simple paiement de l'acheteur. Les ordres `buy` restent
/// publiés et visibles (utile pour signaler la demande et attirer des
/// vendeurs) mais ne s'exécutent pas automatiquement — sans VM à
/// contrats intelligents pour séquestrer les DORO d'un acheteur au
/// moment de la publication, il n'existe pas de mécanisme trustless
/// symétrique pour ce sens. Extension naturelle future : escrow par
/// ordre (comme `EscrowAddress` mais par `orderId`), remboursable à
/// l'annulation via la même mécanique protocolaire que `claimPayout`.
class ShareOrder {
  final String id;
  final String eventId;
  final String outcome; // "yes" | "no"
  final String makerId;
  final String makerPublicKey;
  final OrderSide side;
  final BigInt shares;
  final BigInt filledShares;
  final BigInt pricePerShare; // unités atomiques DORO, 0 < prix < 1 DORO
  final int timestamp;
  final String signature;
  final bool cancelled;

  const ShareOrder({
    required this.id,
    required this.eventId,
    required this.outcome,
    required this.makerId,
    required this.makerPublicKey,
    required this.side,
    required this.shares,
    required this.filledShares,
    required this.pricePerShare,
    required this.timestamp,
    required this.signature,
    this.cancelled = false,
  });

  BigInt get remaining => shares - filledShares;
  bool get isOpen => !cancelled && remaining > BigInt.zero;

  String get hash {
    final raw = [id, eventId, outcome, makerId, side.name, shares.toString(), pricePerShare.toString(), timestamp.toString()].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  ShareOrder copyWith({BigInt? filledShares, bool? cancelled}) => ShareOrder(
        id: id, eventId: eventId, outcome: outcome, makerId: makerId, makerPublicKey: makerPublicKey,
        side: side, shares: shares, filledShares: filledShares ?? this.filledShares,
        pricePerShare: pricePerShare, timestamp: timestamp, signature: signature,
        cancelled: cancelled ?? this.cancelled,
      );

  Map<String, dynamic> toJson() => {
        "id": id, "eventId": eventId, "outcome": outcome, "makerId": makerId, "makerPublicKey": makerPublicKey,
        "side": side.name, "shares": shares.toString(), "filledShares": filledShares.toString(),
        "pricePerShare": pricePerShare.toString(), "timestamp": timestamp, "signature": signature,
        "cancelled": cancelled,
      };

  factory ShareOrder.fromJson(Map<String, dynamic> json) => ShareOrder(
        id: json["id"] as String,
        eventId: json["eventId"] as String,
        outcome: json["outcome"] as String,
        makerId: json["makerId"] as String,
        makerPublicKey: json["makerPublicKey"] as String,
        side: (json["side"] as String) == "buy" ? OrderSide.buy : OrderSide.sell,
        shares: BigInt.parse(json["shares"] as String),
        filledShares: BigInt.tryParse(json["filledShares"] as String? ?? "0") ?? BigInt.zero,
        pricePerShare: BigInt.parse(json["pricePerShare"] as String),
        timestamp: json["timestamp"] as int,
        signature: json["signature"] as String? ?? "",
        cancelled: json["cancelled"] as bool? ?? false,
      );
}

/// Une exécution (fill) déjà réglée — sert d'historique de prix RÉELS
/// pour le graphe (jamais une valeur inventée), exactement dans l'esprit
/// de `TradeRepository.confirmedHistory()` pour le carnet DORO/fiat.
class ShareFill {
  final String id; // = txId du paiement DORO, unique par construction
  final String eventId;
  final String outcome;
  final BigInt shares;
  final BigInt pricePerShare;
  final int timestamp;

  const ShareFill({
    required this.id,
    required this.eventId,
    required this.outcome,
    required this.shares,
    required this.pricePerShare,
    required this.timestamp,
  });
}
