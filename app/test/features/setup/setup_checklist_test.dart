import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/features/setup/widgets/setup_checklist.dart';

class FakeSetup implements PhoneSetup {
  FakeSetup(this.current);

  SetupStatus current;
  int notificationAsks = 0;
  int batteryAsks = 0;

  @override
  Future<SetupStatus> status() async => current;

  @override
  Future<void> askNotifications() async => notificationAsks++;

  @override
  Future<void> askBattery() async => batteryAsks++;
}

Future<void> _show(WidgetTester tester, PhoneSetup setup) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: gotitTheme(Brightness.dark),
      home: Scaffold(body: SetupChecklist(setup: setup)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists what is left, with a count', (tester) async {
    final setup = FakeSetup(const SetupStatus(battery: true));
    await _show(tester, setup);
    expect(find.text('Finish setup'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Allow'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open'), findsNothing);
  });

  testWidgets('the buttons open the right steps', (tester) async {
    final setup = FakeSetup(const SetupStatus());
    await _show(tester, setup);
    await tester.tap(find.widgetWithText(TextButton, 'Allow'));
    await tester.tap(find.widgetWithText(TextButton, 'Open'));
    expect(setup.notificationAsks, 1);
    expect(setup.batteryAsks, 1);
  });

  testWidgets('a step saved just after its page closes is still caught', (
    tester,
  ) async {
    final setup = FakeSetup(const SetupStatus(notifications: true));
    await _show(tester, setup);
    expect(find.text('1 of 2'), findsOneWidget);

    // Back from the battery page before it saved.
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);

    setup.current = const SetupStatus(notifications: true, battery: true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Finish setup'), findsNothing);
  });

  testWidgets('goes away once everything is done', (tester) async {
    final setup = FakeSetup(
      const SetupStatus(notifications: true, battery: true),
    );
    await _show(tester, setup);
    expect(find.text('Finish setup'), findsNothing);
  });
}
