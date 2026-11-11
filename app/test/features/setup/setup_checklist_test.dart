import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/features/setup/widgets/setup_checklist.dart';

class FakeSetup implements PhoneSetup {
  FakeSetup({
    this.notifications = false,
    this.battery = false,
    this.watcher = WatcherState.off,
    this.restricted = false,
    this.maker = '',
    this.tileSupported = false,
  });

  bool notifications;
  bool battery;
  WatcherState watcher;
  bool restricted;
  String maker;
  bool autostart = false;
  bool autostartOpened = false;
  bool locked = false;
  bool tileSupported;
  bool tile = false;

  final asked = <String>[];
  // Closed in tearDown.
  // ignore: close_sinks
  final watcherEvents = StreamController<WatcherState>.broadcast();

  @override
  Future<SetupStatus> status() async => SetupStatus(
    notifications: notifications,
    battery: battery,
    watcher: watcher,
    restricted: restricted,
    autostart: autostart,
    autostartOpened: autostartOpened,
    locked: locked,
    tileSupported: tileSupported,
    tile: tile,
    maker: maker,
  );

  @override
  Future<void> askNotifications() async => asked.add('notifications');

  @override
  Future<void> askBattery() async => asked.add('battery');

  @override
  Future<void> openWatcher() async => asked.add('watcher');

  @override
  Future<void> openAppInfo() async => asked.add('appInfo');

  @override
  Future<void> openAutostart() async {
    asked.add('autostart');
    autostartOpened = true;
  }

  @override
  Future<void> mark(String step) async {
    if (step == 'autostart') autostart = true;
    if (step == 'locked') locked = true;
  }

  @override
  Future<void> addTile() async {
    asked.add('tile');
    tile = true;
  }

  @override
  Stream<WatcherState> get watcherChanges => watcherEvents.stream;
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

Finder _button(String label) => find.widgetWithText(TextButton, label);

void main() {
  late FakeSetup setup;

  tearDown(() => setup.watcherEvents.close());

  testWidgets('lists what is left, with a count', (tester) async {
    setup = FakeSetup(battery: true);
    await _show(tester, setup);
    expect(find.text('Finish setup'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Copy watching'), findsOneWidget);
    expect(_button('Allow'), findsOneWidget);
    // Battery is done, so only the watcher's Open is left.
    expect(_button('Open'), findsOneWidget);
  });

  testWidgets('the buttons open the right steps', (tester) async {
    setup = FakeSetup();
    await _show(tester, setup);
    await tester.tap(_button('Allow'));
    await tester.tap(_button('Open').at(0));
    await tester.tap(_button('Open').at(1));
    expect(setup.asked, ['notifications', 'battery', 'watcher']);
  });

  testWidgets('a step saved just after its page closes is still caught', (
    tester,
  ) async {
    setup = FakeSetup(notifications: true, watcher: WatcherState.on);
    await _show(tester, setup);
    expect(find.text('2 of 3'), findsOneWidget);

    // Back from the battery page before it saved.
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);

    setup.battery = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Finish setup'), findsNothing);
  });

  testWidgets('goes away once everything is done', (tester) async {
    setup = FakeSetup(
      notifications: true,
      battery: true,
      watcher: WatcherState.on,
    );
    await _show(tester, setup);
    expect(find.text('Finish setup'), findsNothing);
  });

  testWidgets('a watcher MIUI stopped says so', (tester) async {
    setup = FakeSetup(
      notifications: true,
      battery: true,
      watcher: WatcherState.stopped,
      restricted: true,
    );
    await _show(tester, setup);
    expect(find.text('Stopped. Switch it off and on again'), findsOneWidget);
    expect(_button('App info'), findsNothing);
  });

  testWidgets('a watcher Android switched off says so', (tester) async {
    setup = FakeSetup(
      notifications: true,
      battery: true,
      watcher: WatcherState.turnedOff,
      restricted: true,
    );
    await _show(tester, setup);
    expect(find.text('Turned off. Switch it on again'), findsOneWidget);
    // An update may have greyed the switch out again.
    expect(_button('App info'), findsOneWidget);
    await tester.tap(_button('Open'));
    expect(setup.asked, ['watcher']);
  });

  testWidgets('a restricted app gets the way to App info', (tester) async {
    setup = FakeSetup(notifications: true, battery: true, restricted: true);
    await _show(tester, setup);
    expect(
      find.text('Greyed out? Allow restricted settings in App info'),
      findsOneWidget,
    );
    await tester.tap(_button('App info'));
    expect(setup.asked, ['appInfo']);
  });

  testWidgets('follows the watcher as it starts', (tester) async {
    setup = FakeSetup(notifications: true, battery: true);
    await _show(tester, setup);
    expect(find.text('2 of 3'), findsOneWidget);

    setup.watcher = WatcherState.on;
    setup.watcherEvents.add(WatcherState.on);
    await tester.pumpAndSettle();
    expect(find.text('Finish setup'), findsNothing);
  });

  testWidgets('offers the quick settings tile where Android can add it', (
    tester,
  ) async {
    setup = FakeSetup(
      notifications: true,
      battery: true,
      watcher: WatcherState.on,
      tileSupported: true,
    );
    await _show(tester, setup);
    expect(find.text('3 of 4'), findsOneWidget);
    expect(find.text('Quick settings tile'), findsOneWidget);

    // Answered either way, the step is done.
    await tester.tap(_button('Add'));
    await tester.pumpAndSettle();
    expect(setup.asked, ['tile']);
    expect(find.text('Finish setup'), findsNothing);
  });

  testWidgets('on Xiaomi, Autostart and the lock are marked done by you', (
    tester,
  ) async {
    setup = FakeSetup(
      notifications: true,
      battery: true,
      watcher: WatcherState.on,
      maker: 'Xiaomi',
    );
    await _show(tester, setup);
    expect(find.text('3 of 5'), findsOneWidget);
    expect(find.text('Recents: hold Gotit, tap the lock'), findsOneWidget);

    // Autostart: open its page first, then Done.
    await tester.tap(_button('Open'));
    await tester.pumpAndSettle();
    expect(setup.asked, ['autostart']);
    expect(_button('Done'), findsNWidgets(2));

    await tester.tap(_button('Done').at(0));
    await tester.pumpAndSettle();
    expect(find.text('4 of 5'), findsOneWidget);

    await tester.tap(_button('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Finish setup'), findsNothing);
  });
}
