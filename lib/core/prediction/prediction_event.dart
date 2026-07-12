// lib/core/prediction/prediction_event.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Un marché de pari binaire façon Polymarket : une question dont
/// l'issue sera OUI ou NON, réglée par un `oracleAddress` désigné à la
/// création (peut être le créateur lui-même, un tiers de confiance, ou —
/// plus tard — un multi-sig ; ce module ne prend pas parti là-dessus,
/// il vérifie juste UNE signature contre l'adresse déclarée).
///
/// Diffusé en flood-gossip et vérifié par chaque pair EXACTEMENT comme
/// un `Order` du carnet OTC existant (voir MarketKernel) : signé par son
/// créateur, dédupliqué par id, rejeté si mal formé ou mal signé.
enum PredictionOutcome { yes, no }

class PredictionEvent {
  final String id;
  final String question;
  final String creatorId;
  final String creatorPublicKey;

  /// Seule adresse dont la signature sur un message `event_resolve` sera
  /// acceptée pour clore ce marché. Choisie librement par le créateur au
  /// moment de la création — souvent lui-même, mais peut être n'importe
  /// quelle adresse (ex: un tiers reconnu comme source de vérité pour
  /// l'événement du monde réel concerné).
  final String oracleAddress;
  final String oraclePublicKey;

  final int createdAt;

  /// Après cet horodatage, plus aucun nouveau "complete set" ne peut être
  /// émis (mais le carnet d'ordres reste ouvert jusqu'à résolution — les
  /// parts déjà émises continuent de s'échanger).
  final int closesAt;

  final String creatorSignature;

  /// Rempli uniquement après résolution.
  final PredictionOutcome? winningOutcome;
  final String? resolutionSignature;
  final int? resolvedAt;

  const PredictionEvent({
    required this.id,
    required this.question,
    required this.creatorId,
    required this.creatorPublicKey,
    required this.oracleAddress,
    required this.oraclePublicKey,
    required this.createdAt,
    required this.closesAt,
    required this.creatorSignature,
    this.winningOutcome,
    this.resolutionSignature,
    this.resolvedAt,
  });

  bool get isResolved => winningOutcome != null;

  /// Empreinte signée à la création — n'inclut PAS les champs de
  /// résolution (signés séparément par le message `event_resolve`, voir
  /// `resolutionMessage`).
  String get creationHash {
    final raw = [id, question, creatorId, creatorPublicKey, oracleAddress, oraclePublicKey, createdAt.toString(), closesAt.toString()].join('|');
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  /// Message exact signé par l'oracle pour résoudre l'événement — inclut
  /// `id` pour empêcher un rejeu de cette signature sur un autre event,
  /// et l'issue elle-même. Volontairement simple et déterministe : tout
  /// pair peut le reconstruire et vérifier la signature sans ambiguïté.
  static String resolutionMessage(String eventId, PredictionOutcome outcome) =>
      "resolve:$eventId:${outcome.name}";

  PredictionEvent copyWithResolution({
    required PredictionOutcome outcome,
    required String signature,
    required int resolvedAt,
  }) =>
      PredictionEvent(
        id: id, question: question, creatorId: creatorId, creatorPublicKey: creatorPublicKey,
        oracleAddress: oracleAddress, oraclePublicKey: oraclePublicKey,
        createdAt: createdAt, closesAt: closesAt, creatorSignature: creatorSignature,
        winningOutcome: outcome, resolutionSignature: signature, resolvedAt: resolvedAt,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "question": question,
        "creatorId": creatorId,
        "creatorPublicKey": creatorPublicKey,
        "oracleAddress": oracleAddress,
        "oraclePublicKey": oraclePublicKey,
        "createdAt": createdAt,
        "closesAt": closesAt,
        "creatorSignature": creatorSignature,
        "winningOutcome": winningOutcome?.name,
        "resolutionSignature": resolutionSignature,
        "resolvedAt": resolvedAt,
      };

  factory PredictionEvent.fromJson(Map<String, dynamic> json) => PredictionEvent(
        id: json["id"] as String,
        question: json["question"] as String,
        creatorId: json["creatorId"] as String,
        creatorPublicKey: json["creatorPublicKey"] as String? ?? "",
        oracleAddress: json["oracleAddress"] as String,
        oraclePublicKey: json["oraclePublicKey"] as String,
        createdAt: json["createdAt"] as int,
        closesAt: json["closesAt"] as int,
        creatorSignature: json["creatorSignature"] as String? ?? "",
        winningOutcome: json["winningOutcome"] == null
            ? null
            : (json["winningOutcome"] == "yes" ? PredictionOutcome.yes : PredictionOutcome.no),
        resolutionSignature: json["resolutionSignature"] as String?,
        resolvedAt: json["resolvedAt"] as int?,
      );
}
