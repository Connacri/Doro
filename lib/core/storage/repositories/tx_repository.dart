import '../entities/tx_entity.dart';
import 'package:objectbox/objectbox.dart';

class TxRepository {
  final Box<TxEntity> box;

  TxRepository(this.box);

  void save(TxEntity tx) {
    box.put(tx);
  }

  List<TxEntity> getAll() {
    return box.getAll();
  }
}