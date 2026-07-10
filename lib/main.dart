import 'package:flutter/material.dart';
import 'app.dart';
import 'core/storage/objectbox/store.dart';
import 'core/utils/logger.dart';

void main() async {
  Logger.info("Démarrage de Doro…");
  WidgetsFlutterBinding.ensureInitialized();
  Logger.info("Flutter binding initialisé");

  final db = ObjectBoxStore();
  Logger.info("Ouverture de la base ObjectBox…");
  await db.init();
  Logger.info("Base ObjectBox prête");

  runApp(DoroApp(db: db));
}
