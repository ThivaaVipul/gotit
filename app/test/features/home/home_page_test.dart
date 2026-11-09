import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/features/home/view/home_page.dart';

void main() {
  testWidgets('shows the name and the version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(loadVersion: () async => '0.1.0')),
    );
    await tester.pump();

    expect(find.text('Gotit'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
  });
}
