// lib/core/storage/entities/bet_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class BetEntity {
  int id = 0;

  @Index()
  @Unique()
  final String betId;
  final String creatorId;
  final String creatorPublicKey;
  final String title;
  final String description;
  final String category;
  final String optionLabelsCsv; // options jointes par '|' (labels simples, pas de '|' dans un label)
  final String minStake;
  final int feeBasisPoints;
  final int stakingDeadline;
  final int votingDeadline;
  final int quorumBasisPoints;
  final int majorityBasisPoints;
  final int timestamp;
  final String signature;

  /// "open" | "voting" | "settled" | "refunded"
  String status;
  String? winningOptionLabel;

  BetEntity({
    this.id = 0,
    required this.betId,
    required this.creatorId,
    required this.creatorPublicKey,
    required this.title,
    required this.description,
    required this.category,
    required this.optionLabelsCsv,
    required this.minStake,
    required this.feeBasisPoints,
    required this.stakingDeadline,
    required this.votingDeadline,
    required this.quorumBasisPoints,
    required this.majorityBasisPoints,
    required this.timestamp,
    required this.signature,
    this.status = "open",
    this.winningOptionLabel,
  });
}
