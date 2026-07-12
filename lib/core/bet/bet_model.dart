// lib/core/bet/bet_model.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Comment le pari est tranché. Un seul mode implémenté pour l'instant :
/// vote communautaire pondéré 1 nodeId = 1 voix parmi les stakers.
enum BetResolutionMode { communityVote }

enum BetStatus {
  open, // accepte des mises
  voting, // deadline de mise dépassée, fenêtre de vote ouverte
  settled, // résolu avec option gagnante, payouts en cours/faits
  refunded, // pas de quorum/majorité -> remboursement (aucune mise transférée)
}

/// Un pari — question + options, diffusé en gossip et persisté localement.
/// Signé par son créateur exactement comme un `Order` : c'est une annonce
/// off-chain, pas une transaction DAG. Le VRAI mouvement de DORO n'a lieu
/// qu'au règlement (voir BetKernel._autoSettlePayout), signé par chaque
/// perdant depuis SON PROPRE compte — comme pour un `Transaction.send`
/// classique, personne d'autre que le propriétaire des fonds ne peut
/// jamais signer à sa place.
class Bet {
  final String id;
  final String creatorId; // adresse = clé publique du créateur
  final String creatorPublicKey;
  final String title;
  final String description;
  final String category;
  final List<String> optionLabels;
  final BigInt minStake; // unité atomique DORO
  final int feeBasisPoints; // frais plateforme, ex: 200 = 2%, prélevés au règlement
  final int stakingDeadline; // epoch ms
  final int votingDeadline; // epoch ms
  final int quorumBasisPoints; // ex: 5000 = 50% des stakers distincts doivent voter
  final int majorityBasisPoints; // ex: 6600 = 66% des votes exprimés
  final int timestamp;
  final String signature;

  Bet({
    required this.id,
    required this.creatorId,
    required this.creatorPublicKey,
    required this.title,
    required this.description,
    required this.category,
    required this.optionLabels,
    required this.minStake,
    required this.timestamp,
    required this.signature,
    this.feeBasisPoints = 200,
    this.stakingDeadline = 0,
    this.votingDeadline = 0,
    this.quorumBasisPoints = 5000,
    this.majorityBasisPoints = 6600,
  });

  String get hash {
    final raw = [
      id, creatorId, title, description, category,
      optionLabels.join(','), minStake.toString(), feeBasisPoints.toString(),
      stakingDeadline.toString(), votingDeadline.toString(),
      quorumBasisPoints.toString(), majorityBasisPoints.toString(),
      timestamp.toString(),
    ].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "creatorId": creatorId,
        "creatorPublicKey": creatorPublicKey,
        "title": title,
        "description": description,
        "category": category,
        "optionLabels": optionLabels,
        "minStake": minStake.toString(),
        "feeBasisPoints": feeBasisPoints,
        "stakingDeadline": stakingDeadline,
        "votingDeadline": votingDeadline,
        "quorumBasisPoints": quorumBasisPoints,
        "majorityBasisPoints": majorityBasisPoints,
        "timestamp": timestamp,
        "signature": signature,
      };

  factory Bet.fromJson(Map<String, dynamic> json) => Bet(
        id: json["id"] as String,
        creatorId: json["creatorId"] as String,
        creatorPublicKey: json["creatorPublicKey"] as String,
        title: json["title"] as String,
        description: json["description"] as String? ?? "",
        category: json["category"] as String? ?? "",
        optionLabels: List<String>.from(json["optionLabels"] ?? const []),
        minStake: BigInt.parse(json["minStake"] as String),
        feeBasisPoints: json["feeBasisPoints"] as int? ?? 200,
        stakingDeadline: json["stakingDeadline"] as int? ?? 0,
        votingDeadline: json["votingDeadline"] as int? ?? 0,
        quorumBasisPoints: json["quorumBasisPoints"] as int? ?? 5000,
        majorityBasisPoints: json["majorityBasisPoints"] as int? ?? 6600,
        timestamp: json["timestamp"] as int,
        signature: json["signature"] as String? ?? "",
      );
}

/// Une mise = engagement signé sur une option. Ce n'est PAS un transfert
/// DORO — le solde du staker n'est débité qu'au règlement final (voir
/// BetKernel). C'est l'équivalent d'un `Order` : une annonce publique
/// engageante, pas encore un mouvement de fonds.
class BetStake {
  final String id;
  final String betId;
  final String optionLabel;
  final String stakerId;
  final String stakerPublicKey;
  final BigInt amount;
  final int timestamp;
  final String signature;

  BetStake({
    required this.id,
    required this.betId,
    required this.optionLabel,
    required this.stakerId,
    required this.stakerPublicKey,
    required this.amount,
    required this.timestamp,
    required this.signature,
  });

  String get hash {
    final raw = [id, betId, optionLabel, stakerId, amount.toString(), timestamp.toString()].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "betId": betId,
        "optionLabel": optionLabel,
        "stakerId": stakerId,
        "stakerPublicKey": stakerPublicKey,
        "amount": amount.toString(),
        "timestamp": timestamp,
        "signature": signature,
      };

  factory BetStake.fromJson(Map<String, dynamic> json) => BetStake(
        id: json["id"] as String,
        betId: json["betId"] as String,
        optionLabel: json["optionLabel"] as String,
        stakerId: json["stakerId"] as String,
        stakerPublicKey: json["stakerPublicKey"] as String,
        amount: BigInt.parse(json["amount"] as String),
        timestamp: json["timestamp"] as int,
        signature: json["signature"] as String? ?? "",
      );
}

/// Un vote communautaire sur l'issue réelle. 1 nodeId = 1 voix (jamais
/// pondéré par la mise) pour qu'une grosse mise ne puisse pas acheter le
/// résultat — seuls les nodeId ayant misé sur CE pari peuvent voter.
class BetVote {
  final String id;
  final String betId;
  final String voterId;
  final String voterPublicKey;
  final String votedOptionLabel;
  final int timestamp;
  final String signature;

  BetVote({
    required this.id,
    required this.betId,
    required this.voterId,
    required this.voterPublicKey,
    required this.votedOptionLabel,
    required this.timestamp,
    required this.signature,
  });

  String get hash => "$id|$betId|$voterId|$votedOptionLabel|$timestamp";

  Map<String, dynamic> toJson() => {
        "id": id,
        "betId": betId,
        "voterId": voterId,
        "voterPublicKey": voterPublicKey,
        "votedOptionLabel": votedOptionLabel,
        "timestamp": timestamp,
        "signature": signature,
      };

  factory BetVote.fromJson(Map<String, dynamic> json) => BetVote(
        id: json["id"] as String,
        betId: json["betId"] as String,
        voterId: json["voterId"] as String,
        voterPublicKey: json["voterPublicKey"] as String,
        votedOptionLabel: json["votedOptionLabel"] as String,
        timestamp: json["timestamp"] as int,
        signature: json["signature"] as String? ?? "",
      );
}
