import '../entities/peer_entity.dart';
import 'package:objectbox/objectbox.dart';

class PeerRepository {
  final Box<PeerEntity> box;

  PeerRepository(this.box);

  void upsert(PeerEntity peer) {
    box.put(peer);
  }

  List<PeerEntity> getAll() {
    return box.getAll();
  }

  PeerEntity? findById(String peerId) {
    return box.query(PeerEntity_.peerId.equals(peerId)).build().findFirst();
  }

  void delete(int id) {
    box.remove(id);
  }
}