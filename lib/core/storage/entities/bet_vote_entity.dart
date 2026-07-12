// lib/core/storage/entities/bet_vote_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class BetVoteEntity {
  int id = 0;

  @Index()
  @Unique()
  final String voteId;

  @Index()
  final String betId;
  final String voterId;
  final String voterPublicKey;
  final String votedOptionLabel;
  final int timestamp;
  final String signature;

  BetVoteEntity({
    this.id = 0,
    required this.voteId,
    required this.betId,
    required this.voterId,
    required this.voterPublicKey,
    required this.votedOptionLabel,
    required this.timestamp,
    required this.signature,
  });
}
