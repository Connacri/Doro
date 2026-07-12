// lib/core/storage/entities/outcome_position_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class OutcomePositionEntity {
  int id = 0;

  /// Clé composite logique "eventId:outcome:holderAddress" — unique,
  /// sert de clé d'upsert (voir OutcomePositionRepository).
  @Index()
  @Unique()
  final String positionKey;

  @Index()
  final String eventId;
  final String outcome; // "yes" | "no"
  @Index()
  final String holderAddress;
  String shares; // BigInt sérialisé
  String sharesClaimed; // BigInt sérialisé

  OutcomePositionEntity({
    this.id = 0,
    required this.positionKey,
    required this.eventId,
    required this.outcome,
    required this.holderAddress,
    required this.shares,
    required this.sharesClaimed,
  });
}
