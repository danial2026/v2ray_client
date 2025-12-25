import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v2ray/main.dart';

void main() {
  testWidgets('App initialization smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const V2RayApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
