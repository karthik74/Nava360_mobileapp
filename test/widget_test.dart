import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nava360/app.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: HrmsApp()),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
