import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/release_info.dart';
import 'package:gotit/core/update/update_source.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/features/home/view/home_page.dart';

class _NoSource implements UpdateSource {
  @override
  Future<ReleaseInfo?> latest() async => null;

  @override
  Future<String> fetchText(Uri url) async => '';

  @override
  Future<void> download(
    Uri url,
    File to, {
    void Function(double)? onProgress,
  }) async {}
}

class _NoInstaller implements Installer {
  @override
  ReleaseAsset? assetOf(ReleaseInfo release) => null;

  @override
  bool get automatic => false;

  @override
  Future<InstallOutcome> install(File file) async => InstallOutcome.started;
}

Updater _updater(UpdateState state) => Updater(
  currentVersion: '0.1.0',
  source: _NoSource(),
  installer: _NoInstaller(),
  downloadDir: () async => Directory.systemTemp,
)..value = state;

Future<void> _pump(WidgetTester tester, Updater updater) => tester.pumpWidget(
  MaterialApp(
    home: HomePage(version: '0.1.0', updater: updater),
  ),
);

void main() {
  testWidgets('shows the name and the version', (tester) async {
    await _pump(tester, _updater(const UpdateUpToDate()));
    expect(find.text('Gotit'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
  });

  testWidgets('offers a waiting update with a button', (tester) async {
    await _pump(tester, _updater(const UpdateAvailable('0.2.0')));
    expect(find.text('Version 0.2.0 is ready'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('says so right after an update', (tester) async {
    await _pump(tester, _updater(const UpdateUpToDate(justUpdated: true)));
    expect(find.text('Updated'), findsOneWidget);
  });

  testWidgets('marks a local build', (tester) async {
    await _pump(tester, _updater(const UpdateLocalBuild()));
    expect(find.text('Development build'), findsOneWidget);
  });
}
