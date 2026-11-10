import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/features/pairing/view/pair_code_page.dart';

/// Lets arrivals finish. The waiting spinner never stops, so settling would
/// wait forever.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  late StreamController<PairProgress> steps;

  setUp(() => steps = StreamController<PairProgress>());
  tearDown(() => steps.close());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: gotitTheme(Brightness.dark),
        home: PairCodePage(
          attempt: PairAttempt.fromSteps(steps.stream),
          pcName: 'Desk PC',
        ),
      ),
    );
  }

  testWidgets('shows the code and waits for Accept, then says paired', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Connecting'), findsWidgets);

    steps.add(const PairShowCode(code: '4719', pcName: 'Desk PC'));
    await step(tester);
    expect(find.text('Pair with Desk PC'), findsOneWidget);
    expect(find.text('Check that Desk PC shows this code'), findsOneWidget);
    for (final digit in ['4', '7', '1', '9']) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.text('Waiting for Accept on Desk PC'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

    steps.add(const PairDone(Peer(id: 'pc', name: 'Desk PC', certPem: 'x')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paired'), findsWidgets);
    // It goes home by itself shortly after.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a decline says so and offers to try again', (tester) async {
    await open(tester);
    steps.add(const PairShowCode(code: '4719', pcName: 'Desk PC'));
    await step(tester);
    steps.add(const PairRefused(PairRefusal.declined));
    await step(tester);
    expect(find.text('Declined on Desk PC'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('an unreachable PC asks about the Wi-Fi', (tester) async {
    await open(tester);
    steps.add(const PairFailed());
    await step(tester);
    expect(find.text("Couldn't reach Desk PC. Same Wi-Fi?"), findsOneWidget);
  });
}
