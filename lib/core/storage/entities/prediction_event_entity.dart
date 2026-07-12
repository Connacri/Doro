// lib/core/storage/entities/prediction_event_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class PredictionEventEntity {
  int id = 0;

  @Index()
  @Unique()
  final String eventId;
  final String question;
  final String creatorId;
  final String creatorPublicKey;
  final String oracleAddress;
  final String oraclePublicKey;
  final int createdAt;
  final int closesAt;
  final String creatorSignature;

  String? winningOutcome; // "yes" | "no" | null tant que non résolu
  String? resolutionSignature;
  int? resolvedAt;

  PredictionEventEntity({
    this.id = 0,
    required this.eventId,
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
}
