import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doro/app.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const DoroApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
