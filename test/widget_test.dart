
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Hustlr/widgets/live_activity_overlay.dart';

void main() {
  testWidgets('LiveActivityOverlay renders child content', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LiveActivityOverlay(
            child: Text('Hustlr Home'),
          ),
        ),
      ),
    );

    expect(find.byType(LiveActivityOverlay), findsOneWidget);
    expect(find.text('Hustlr Home'), findsOneWidget);
  });
}
