import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doro/app.dart';
import 'package:doro/core/storage/objectbox/store.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    final db = ObjectBoxStore();
    // We don't initialize the DB here to avoid native dependency issues during simple UI tests.
    await tester.pumpWidget(DoroApp(db: db));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
