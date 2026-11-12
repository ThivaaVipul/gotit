import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/settings.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gotit_settings_');
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('starts from the defaults when there is no file', () async {
    final store = await SettingsStore.open(file);
    expect(store.value, const Settings());
  });

  test('keeps what was saved', () async {
    final store = await SettingsStore.open(file);
    await store.save(
      const Settings(pcName: 'Desk PC', startWithWindows: false),
    );
    final again = await SettingsStore.open(file);
    expect(again.value.pcName, 'Desk PC');
    expect(again.value.startWithWindows, isFalse);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('keeps the sharing switch', () async {
    final off = SharingState(
      on: false,
      changedAt: DateTime(2026, 11, 11, 9),
      by: 'phone',
    );
    final store = await SettingsStore.open(file);
    await store.save(store.value.copyWith(sharing: () => off));
    final again = await SettingsStore.open(file);
    expect(again.value.sharing, off);
  });

  test(
    'screenshots go to the PC unless turned off, and that is kept',
    () async {
      final store = await SettingsStore.open(file);
      expect(store.value.sendsScreenshots, isTrue);
      await store.save(store.value.copyWith(screenshots: () => false));
      final again = await SettingsStore.open(file);
      expect(again.value.sendsScreenshots, isFalse);
    },
  );

  test('a damaged file gives the defaults', () async {
    file.writeAsStringSync('{not json');
    final store = await SettingsStore.open(file);
    expect(store.value, const Settings());
  });

  test('a field can be cleared back to its default', () {
    const settings = Settings(pcName: 'Desk PC', startWithWindows: true);
    final cleared = settings.copyWith(pcName: () => null);
    expect(cleared.pcName, isNull);
    expect(cleared.startWithWindows, isTrue);
    expect(cleared.toJson(), {'startWithWindows': true});
  });
}
