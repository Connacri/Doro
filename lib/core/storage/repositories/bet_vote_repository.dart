// lib/core/storage/repositories/bet_vote_repository.dart
import '../../../objectbox.g.dart';
import '../../bet/bet_model.dart';
import '../entities/bet_vote_entity.dart';
import '../objectbox/store.dart';

class BetVoteRepository {
  final ObjectBoxStore _db;
  Box<BetVoteEntity>? _boxCached;
  BetVoteRepository(this._db);
  Box<BetVoteEntity> get _box => _boxCached ??= _db.getBox<BetVoteEntity>();

  bool exists(String voteId) => _box.query(BetVoteEntity_.voteId.equals(voteId)).build().findFirst() != null;

  bool hasVoted(String betId, String voterId) =>
      (_box.query(BetVoteEntity_.betId.equals(betId) & BetVoteEntity_.voterId.equals(voterId)).build().findFirst()) != null;

  void save(BetVote v) {
    if (exists(v.id)) return;
    _box.put(BetVoteEntity(
      voteId: v.id,
      betId: v.betId,
      voterId: v.voterId,
      voterPublicKey: v.voterPublicKey,
      votedOptionLabel: v.votedOptionLabel,
      timestamp: v.timestamp,
      signature: v.signature,
    ));
  }

  List<BetVote> byBet(String betId) =>
      _box.query(BetVoteEntity_.betId.equals(betId)).build().find().map(_toModel).toList();

  BetVote _toModel(BetVoteEntity e) => BetVote(
        id: e.voteId,
        betId: e.betId,
        voterId: e.voterId,
        voterPublicKey: e.voterPublicKey,
        votedOptionLabel: e.votedOptionLabel,
        timestamp: e.timestamp,
        signature: e.signature,
      );
}
