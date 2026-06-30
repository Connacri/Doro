import 'package:objectbox/objectbox.dart';

class ObjectBoxStore {
  late Store store;

  Future<void> init() async {
    store = await openStore();
  }

  Box<T> box<T>() => store.box<T>();
}