// lib/core/storage/repositories/bet_stake_repository.dart
import '../../../objectbox.g.dart';
import '../../bet/bet_model.dart';
import '../entities/bet_stake_entity.dart';
import '../objectbox/store.dart';

class BetStakeRepository {
  final ObjectBoxStore _db;
  Box<BetStakeEntity>? _boxCached;
  BetStakeRepository(this._db);
  Box<BetStakeEntity> get _box => _boxCached ??= _db.getBox<BetStakeEntity>();

  bool exists(String stakeId) => _box.query(BetStakeEntity_.stakeId.equals(stakeId)).build().findFirst() != null;

  void save(BetStake s) {
    if (exists(s.id)) return;
    _box.put(BetStakeEntity(
      stakeId: s.id,
      betId: s.betId,
      optionLabel: s.optionLabel,
      stakerId: s.stakerId,
      stakerPublicKey: s.stakerPublicKey,
      amount: s.amount.toString(),
      timestamp: s.timestamp,
      signature: s.signature,
    ));
  }

  List<BetStake> byBet(String betId) =>
      _box.query(BetStakeEntity_.betId.equals(betId)).build().find().map(_toModel).toList();

  List<BetStakeEntity> entitiesByBet(String betId) =>
      _box.query(BetStakeEntity_.betId.equals(betId)).build().find();

  void markPaid(String stakeId, {required BigInt amount, required String txId}) {
    final e = _box.query(BetStakeEntity_.stakeId.equals(stakeId)).build().findFirst();
    if (e == null) return;
    e.payoutAmount = amount.toString();
    e.payoutTxId = txId;
    e.defaulted = false;
    _box.put(e);
  }

  void markDefaulted(String stakeId) {
    final e = _box.query(BetStakeEntity_.stakeId.equals(stakeId)).build().findFirst();
    if (e == null) return;
    e.defaulted = true;
    _box.put(e);
  }

  BetStake _toModel(BetStakeEntity e) => BetStake(
        id: e.stakeId,
        betId: e.betId,
        optionLabel: e.optionLabel,
        stakerId: e.stakerId,
        stakerPublicKey: e.stakerPublicKey,
        amount: BigInt.parse(e.amount),
        timestamp: e.timestamp,
        signature: e.signature,
      );
}
