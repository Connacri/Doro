import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doro/app.dart';
import 'package:doro/core/storage/objectbox/store.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    final db = ObjectBoxStore();
    final tempDir = Directory.systemTemp.createTempSync('doro_test_db');
    await db.init(directory: tempDir.path);

    await tester.pumpWidget(DoroApp(db: db));
    expect(find.byType(MaterialApp), findsOneWidget);

    db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
}
