// lib/core/storage/repositories/outcome_position_repository.dart
import '../../../objectbox.g.dart';
import '../../prediction/outcome_position.dart';
import '../entities/outcome_position_entity.dart';
import '../objectbox/store.dart';

class OutcomePositionRepository {
  final ObjectBoxStore _db;
  Box<OutcomePositionEntity>? _boxCached;
  OutcomePositionRepository(this._db);
  Box<OutcomePositionEntity> get _box => _boxCached ??= _db.getBox<OutcomePositionEntity>();

  static String _key(String eventId, String outcome, String holder) => "$eventId:$outcome:$holder";

  OutcomePosition get(String eventId, String outcome, String holder) {
    final key = _key(eventId, outcome, holder);
    final e = _box.query(OutcomePositionEntity_.positionKey.equals(key)).build().findFirst();
    if (e == null) {
      return OutcomePosition(eventId: eventId, outcome: outcome, holderAddress: holder, shares: BigInt.zero, sharesClaimed: BigInt.zero);
    }
    return _toModel(e);
  }

  /// Ajoute (ou retire, si négatif) `deltaShares` à la position — utilisé
  /// par le mint (crédit), un trade réglé (transfert de propriété), ou un
  /// merge (débit). Jamais laissé descendre sous zéro.
  void addShares(String eventId, String outcome, String holder, BigInt deltaShares) {
    final key = _key(eventId, outcome, holder);
    final existing = _box.query(OutcomePositionEntity_.positionKey.equals(key)).build().findFirst();
    if (existing == null) {
      if (deltaShares <= BigInt.zero) return;
      _box.put(OutcomePositionEntity(
        positionKey: key, eventId: eventId, outcome: outcome, holderAddress: holder,
        shares: deltaShares.toString(), sharesClaimed: "0",
      ));
      return;
    }
    final newShares = BigInt.parse(existing.shares) + deltaShares;
    existing.shares = (newShares < BigInt.zero ? BigInt.zero : newShares).toString();
    _box.put(existing);
  }

  void markClaimed(String eventId, String outcome, String holder, BigInt claimedNow) {
    final key = _key(eventId, outcome, holder);
    final existing = _box.query(OutcomePositionEntity_.positionKey.equals(key)).build().findFirst();
    if (existing == null) return;
    existing.sharesClaimed = (BigInt.parse(existing.sharesClaimed) + claimedNow).toString();
    _box.put(existing);
  }

  List<OutcomePosition> positionsForEvent(String eventId) =>
      _box.query(OutcomePositionEntity_.eventId.equals(eventId)).build().find().map(_toModel).toList();

  List<OutcomePosition> positionsForHolder(String holder) =>
      _box.query(OutcomePositionEntity_.holderAddress.equals(holder)).build().find().map(_toModel).toList();

  OutcomePosition _toModel(OutcomePositionEntity e) => OutcomePosition(
        eventId: e.eventId, outcome: e.outcome, holderAddress: e.holderAddress,
        shares: BigInt.parse(e.shares), sharesClaimed: BigInt.parse(e.sharesClaimed),
      );
}
