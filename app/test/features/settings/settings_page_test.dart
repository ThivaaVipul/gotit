import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/features/settings/view/settings_page.dart';

import '../../helpers.dart';

void main() {
  late Directory dir;
  late SettingsStore settings;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('gotit_settings_page_');
    settings = await SettingsStore.open(File('${dir.path}/settings.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppServices> pump(WidgetTester tester, {StartupEntry? startup}) async {
    final services = AppServices(
      version: '0.3.0',
      updater: noUpdates(const UpdateUpToDate()),
      settings: settings,
      isPc: true,
      startup: startup,
      windowsName: 'WORKSTATION-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: gotitTheme(Brightness.dark),
        home: SettingsPage(services: services),
      ),
    );
    return services;
  }

  testWidgets('shows the Windows name until another is chosen', (tester) async {
    await pump(tester);
    expect(find.widgetWithText(TextField, 'WORKSTATION-1'), findsOneWidget);
  });

  testWidgets('saves a new name on Enter', (tester) async {
    final services = await pump(tester);
    await tester.enterText(find.byType(TextField), 'Desk PC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(settings.value.pcName, 'Desk PC');
    expect(services.pcName, 'Desk PC');
  });

  testWidgets('clearing the name goes back to the Windows name', (
    tester,
  ) async {
    await tester.runAsync(
      () => settings.save(const Settings(pcName: 'Desk PC')),
    );
    await pump(tester);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(settings.value.pcName, isNull);
    expect(find.widgetWithText(TextField, 'WORKSTATION-1'), findsOneWidget);
  });

  testWidgets('start with Windows is off limits in a local build', (
    tester,
  ) async {
    await pump(tester);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNull);
    expect(find.text('Installed copies only'), findsOneWidget);
  });

  testWidgets('turning start with Windows off removes it', (tester) async {
    final entry = FakeEntry()..isOn = true;
    await tester.runAsync(
      () => settings.save(const Settings(startWithWindows: true)),
    );
    await pump(tester, startup: entry);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(entry.isOn, isFalse);
    expect(settings.value.startWithWindows, isFalse);
  });
}
