import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/features/home/view/home_page.dart';

import '../../helpers.dart';

late SettingsStore _settings;

Future<void> _pump(WidgetTester tester, UpdateState state) => tester.pumpWidget(
  MaterialApp(
    home: HomePage(
      services: AppServices(
        version: '0.1.0',
        updater: noUpdates(state),
        settings: _settings,
        isPc: false,
      ),
    ),
  ),
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('gotit_home_');
    _settings = await SettingsStore.open(File('${dir.path}/settings.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('shows the name and the version', (tester) async {
    await _pump(tester, const UpdateUpToDate());
    expect(find.text('Gotit'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
  });

  testWidgets('offers a waiting update with a button', (tester) async {
    await _pump(tester, const UpdateAvailable('0.2.0'));
    expect(find.text('Version 0.2.0 is ready'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('says so right after an update', (tester) async {
    await _pump(tester, const UpdateUpToDate(justUpdated: true));
    expect(find.text('Updated'), findsOneWidget);
  });

  testWidgets('marks a local build', (tester) async {
    await _pump(tester, const UpdateLocalBuild());
    expect(find.text('Development build'), findsOneWidget);
  });
}
