import 'store.dart';

class ObjectBoxInit {
  final ObjectBoxStore db;

  ObjectBoxInit(this.db);

  Future<void> init() async {
    await db.init();
  }
}