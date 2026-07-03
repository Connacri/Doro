import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../objectbox.g.dart'; // This will be generated

class ObjectBoxStore {
  Store? _store;

  Future<void> init({String? directory}) async {
    final String storeDir;
    if (directory != null) {
      storeDir = directory;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      storeDir = p.join(docsDir.path, "doro-db");
    }
    if (!Directory(storeDir).existsSync()) {
      await Directory(storeDir).create(recursive: true);
    }
    _store = await openStore(directory: storeDir);
  }

  Store get store => _store!;

  Box<T> getBox<T>() => _store!.box<T>();

  void close() {
    _store?.close();
  }
}
