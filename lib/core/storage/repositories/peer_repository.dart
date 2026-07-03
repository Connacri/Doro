import '../../../objectbox.g.dart';

import '../entities/peer_entity.dart';
import '../objectbox/store.dart';

class PeerRepository {
  final ObjectBoxStore _db;
  late final Box<PeerEntity> _box;

  PeerRepository(this._db) {
    _box = _db.getBox<PeerEntity>();
  }

  void upsert(PeerEntity peer) {
    final existing = _box.query(PeerEntity_.peerId.equals(peer.peerId)).build().findFirst();
    if (existing != null) {
      peer.id = existing.id;
    }
    _box.put(peer);
  }

  List<PeerEntity> getAll() {
    return _box.getAll();
  }

  PeerEntity? findById(String peerId) {
    return _box.query(PeerEntity_.peerId.equals(peerId)).build().findFirst();
  }

  void delete(String peerId) {
    final peer = findById(peerId);
    if (peer != null) {
      _box.remove(peer.id);
    }
  }
}
