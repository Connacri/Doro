// lib/core/storage/repositories/prediction_event_repository.dart
import '../../../objectbox.g.dart';
import '../../prediction/prediction_event.dart';
import '../entities/prediction_event_entity.dart';
import '../objectbox/store.dart';

class PredictionEventRepository {
  final ObjectBoxStore _db;
  Box<PredictionEventEntity>? _boxCached;
  PredictionEventRepository(this._db);
  Box<PredictionEventEntity> get _box => _boxCached ??= _db.getBox<PredictionEventEntity>();

  bool exists(String eventId) =>
      _box.query(PredictionEventEntity_.eventId.equals(eventId)).build().findFirst() != null;

  void save(PredictionEvent e) {
    final existing = _box.query(PredictionEventEntity_.eventId.equals(e.id)).build().findFirst();
    if (existing != null) {
      existing.winningOutcome = e.winningOutcome?.name;
      existing.resolutionSignature = e.resolutionSignature;
      existing.resolvedAt = e.resolvedAt;
      _box.put(existing);
      return;
    }
    _box.put(PredictionEventEntity(
      eventId: e.id, question: e.question, creatorId: e.creatorId, creatorPublicKey: e.creatorPublicKey,
      oracleAddress: e.oracleAddress, oraclePublicKey: e.oraclePublicKey,
      createdAt: e.createdAt, closesAt: e.closesAt, creatorSignature: e.creatorSignature,
      winningOutcome: e.winningOutcome?.name, resolutionSignature: e.resolutionSignature,
      resolvedAt: e.resolvedAt,
    ));
  }

  PredictionEvent? get(String eventId) {
    final e = _box.query(PredictionEventEntity_.eventId.equals(eventId)).build().findFirst();
    return e == null ? null : _toModel(e);
  }

  List<PredictionEvent> all() => _box.getAll().map(_toModel).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<PredictionEvent> openEvents() => all().where((e) => !e.isResolved).toList();
  List<PredictionEvent> resolvedEvents() => all().where((e) => e.isResolved).toList();

  PredictionEvent _toModel(PredictionEventEntity e) => PredictionEvent(
        id: e.eventId, question: e.question, creatorId: e.creatorId, creatorPublicKey: e.creatorPublicKey,
        oracleAddress: e.oracleAddress, oraclePublicKey: e.oraclePublicKey,
        createdAt: e.createdAt, closesAt: e.closesAt, creatorSignature: e.creatorSignature,
        winningOutcome: e.winningOutcome == null
            ? null
            : (e.winningOutcome == "yes" ? PredictionOutcome.yes : PredictionOutcome.no),
        resolutionSignature: e.resolutionSignature, resolvedAt: e.resolvedAt,
      );
}
