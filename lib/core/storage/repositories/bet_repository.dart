// lib/core/storage/repositories/bet_repository.dart
import '../../../objectbox.g.dart';
import '../../bet/bet_model.dart';
import '../entities/bet_entity.dart';
import '../objectbox/store.dart';

class BetRepository {
  final ObjectBoxStore _db;
  Box<BetEntity>? _boxCached;
  BetRepository(this._db);
  Box<BetEntity> get _box => _boxCached ??= _db.getBox<BetEntity>();

  bool exists(String betId) => _box.query(BetEntity_.betId.equals(betId)).build().findFirst() != null;

  void save(Bet b) {
    if (exists(b.id)) return;
    _box.put(BetEntity(
      betId: b.id,
      creatorId: b.creatorId,
      creatorPublicKey: b.creatorPublicKey,
      title: b.title,
      description: b.description,
      category: b.category,
      optionLabelsCsv: b.optionLabels.join('|'),
      minStake: b.minStake.toString(),
      feeBasisPoints: b.feeBasisPoints,
      stakingDeadline: b.stakingDeadline,
      votingDeadline: b.votingDeadline,
      quorumBasisPoints: b.quorumBasisPoints,
      majorityBasisPoints: b.majorityBasisPoints,
      timestamp: b.timestamp,
      signature: b.signature,
    ));
  }

  BetEntity? entity(String betId) => _box.query(BetEntity_.betId.equals(betId)).build().findFirst();

  void updateStatus(String betId, String status, {String? winningOptionLabel}) {
    final e = entity(betId);
    if (e == null) return;
    e.status = status;
    if (winningOptionLabel != null) e.winningOptionLabel = winningOptionLabel;
    _box.put(e);
  }

  List<Bet> openBets() =>
      _box.query(BetEntity_.status.equals("open")).build().find().map(_toModel).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<Bet> awaitingVoteOrSettlement() =>
      _box.query(BetEntity_.status.equals("open") | BetEntity_.status.equals("voting")).build().find().map(_toModel).toList();

  List<Bet> all() => _box.getAll().map(_toModel).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  Bet _toModel(BetEntity e) => Bet(
        id: e.betId,
        creatorId: e.creatorId,
        creatorPublicKey: e.creatorPublicKey,
        title: e.title,
        description: e.description,
        category: e.category,
        optionLabels: e.optionLabelsCsv.split('|'),
        minStake: BigInt.parse(e.minStake),
        feeBasisPoints: e.feeBasisPoints,
        stakingDeadline: e.stakingDeadline,
        votingDeadline: e.votingDeadline,
        quorumBasisPoints: e.quorumBasisPoints,
        majorityBasisPoints: e.majorityBasisPoints,
        timestamp: e.timestamp,
        signature: e.signature,
      );
}
