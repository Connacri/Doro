import 'package:flutter/material.dart';
import 'app.dart';
import 'core/storage/objectbox/store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = ObjectBoxStore();
  await db.init();

  runApp(DoroApp(db: db));
}
