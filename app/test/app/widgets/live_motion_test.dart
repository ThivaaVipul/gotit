import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/app/widgets/device_node.dart';
import 'package:gotit/app/widgets/sweep_card.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: gotitTheme(Brightness.dark),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Center(child: child),
  ),
);

Future<void> _comeBack(WidgetTester tester) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

final _ring = find.descendant(
  of: find.byType(DeviceNode),
  matching: find.byType(Transform),
);

void main() {
  testWidgets('the sweep turns once when live, then rests', (tester) async {
    await tester.pumpWidget(
      _app(const SweepCard(live: true, child: Text('PC'))),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    // An endless sweep would never settle.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the sweep turns again when the app comes back', (tester) async {
    await tester.pumpWidget(
      _app(const SweepCard(live: true, child: Text('PC'))),
    );
    await tester.pumpAndSettle();
    await _comeBack(tester);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('the ring pulses a few times when live, then is gone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const DeviceNode(icon: Icons.computer, live: true)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_ring, findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_ring, findsNothing);

    await _comeBack(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_ring, findsOneWidget);
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
  });

  testWidgets('both stay still when the system asks for less motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SweepCard(live: true, child: Text('PC')),
            DeviceNode(icon: Icons.computer, live: true),
          ],
        ),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(_ring, findsNothing);
  });
}
