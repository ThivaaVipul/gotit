import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/features/pairing/widgets/pair_request_sheet.dart';

void main() {
  PairRequest request({String? replaces}) => PairRequest.forTest(
    phoneName: 'Test phone',
    code: '0815',
    expiresAt: DateTime.now().add(const Duration(seconds: 60)),
    replaces: replaces,
  );

  Future<void> show(WidgetTester tester, PairRequest request) =>
      tester.pumpWidget(
        MaterialApp(
          theme: gotitTheme(Brightness.light),
          home: Scaffold(body: PairRequestSheet(request: request)),
        ),
      );

  testWidgets('shows who asks and the code to compare', (tester) async {
    await show(tester, request());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Test phone wants to pair'), findsOneWidget);
    for (final digit in ['0', '8', '1', '5']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.textContaining('Replaces'), findsNothing);
  });

  testWidgets('Accept accepts', (tester) async {
    final asked = request();
    await show(tester, asked);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    expect(await asked.decided, isTrue);
  });

  testWidgets('Decline declines', (tester) async {
    final asked = request();
    await show(tester, asked);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    expect(await asked.decided, isFalse);
  });

  testWidgets('says which phone it replaces', (tester) async {
    await show(tester, request(replaces: 'Old phone'));
    expect(find.text('Replaces Old phone'), findsOneWidget);
  });
}
