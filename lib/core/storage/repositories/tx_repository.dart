import '../../../objectbox.g.dart';
import '../../dag/transaction_model.dart';
import '../entities/tx_entity.dart';
import '../objectbox/store.dart';

/// ⚠️ Limite technique connue : `TxEntity` (schéma ObjectBox) n'a pas de
/// colonne pour `type` (send/receive) ni `linkedSendId` — les ajouter
/// proprement demande de régénérer `objectbox.g.dart` via `build_runner`,
/// impossible à faire depuis cet environnement (pas d'accès à `dart`/
/// `flutter pub`). En attendant, on encode ces deux infos DANS la colonne
/// `parents` existante, derrière un séparateur `;` qu'un id de parent
/// (toujours un hash sha256 hexadécimal à 64 caractères, jamais de `;`)
/// ne peut pas produire — donc aucune ambiguïté de parsing possible.
///
/// À FAIRE dès que possible sur ta machine : lance
/// `flutter pub run build_runner build` après avoir ajouté `type` (String)
/// et `linkedSendId` (String?) à `TxEntity`, puis remplace ce hack par de
/// vraies colonnes. Le format ci-dessous restera lisible pour écrire un
/// script de migration one-shot si besoin.
class TxRepository {
  final ObjectBoxStore _db;
  late final Box<TxEntity> _box;

  static const _marker = ';;DORO_TX_META;;';

  TxRepository(this._db) {
    _box = _db.getBox<TxEntity>();
  }

  String _encodeParents(Transaction tx) {
    final base = tx.parents.join(',');
    if (tx.type == TxType.send) return base;
    return '$base$_marker${tx.type.name}:${tx.linkedSendId ?? ''}';
  }

  ({List<String> parents, TxType type, String? linkedSendId}) _decodeParents(String raw) {
    final markerIndex = raw.indexOf(_marker);
    if (markerIndex == -1) {
      final parents = raw.isEmpty ? const <String>[] : raw.split(',');
      return (parents: parents, type: TxType.send, linkedSendId: null);
    }
    final parentsPart = raw.substring(0, markerIndex);
    final metaPart = raw.substring(markerIndex + _marker.length);
    final sep = metaPart.indexOf(':');
    final typeName = sep == -1 ? metaPart : metaPart.substring(0, sep);
    final linkedSendId = sep == -1 ? null : metaPart.substring(sep + 1);
    final parents = parentsPart.isEmpty ? const <String>[] : parentsPart.split(',');
    return (
      parents: parents,
      type: typeName == 'receive' ? TxType.receive : TxType.send,
      linkedSendId: (linkedSendId == null || linkedSendId.isEmpty) ? null : linkedSendId,
    );
  }

  List<Transaction> all() {
    return _box.getAll().map((e) {
      final decoded = _decodeParents(e.parents);
      return Transaction(
        id: e.txId,
        type: decoded.type,
        from: e.from,
        to: e.to,
        amount: BigInt.parse(e.amount),
        timestamp: e.timestamp,
        signature: e.signature,
        nonce: e.nonce,
        senderPublicKey: e.senderPublicKey,
        parents: decoded.parents,
        linkedSendId: decoded.linkedSendId,
      );
    }).toList();
  }

  Future<void> save(Transaction tx) async {
    final existing = _box.query(TxEntity_.txId.equals(tx.id)).build().findFirst();
    if (existing != null) return;

    _box.put(TxEntity(
      txId: tx.id,
      from: tx.from,
      to: tx.to,
      amount: tx.amount.toString(),
      timestamp: tx.timestamp,
      signature: tx.signature,
      nonce: tx.nonce,
      senderPublicKey: tx.senderPublicKey,
      parents: _encodeParents(tx),
    ));
  }

  Future<void> load() async {
  }
}
