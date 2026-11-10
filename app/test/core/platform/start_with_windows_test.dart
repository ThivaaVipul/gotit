import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/state/settings.dart';

import '../../helpers.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('gotit_startup_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<SettingsStore> store([Settings? settings]) async {
    final store = await SettingsStore.open(File('${dir.path}/settings.json'));
    if (settings != null) await store.save(settings);
    return store;
  }

  test('the first launch turns it on and remembers that', () async {
    final settings = await store();
    final entry = FakeEntry();
    await applyStartWithWindows(settings, entry);
    expect(entry.isOn, isTrue);
    expect(settings.value.startWithWindows, isTrue);
  });

  test('turned off stays off', () async {
    final settings = await store(const Settings(startWithWindows: false));
    final entry = FakeEntry()..isOn = true;
    await applyStartWithWindows(settings, entry);
    expect(entry.isOn, isFalse);
  });

  test('turned on is written again, keeping the path current', () async {
    final settings = await store(const Settings(startWithWindows: true));
    final entry = FakeEntry()..isOn = true;
    await applyStartWithWindows(settings, entry);
    expect(entry.isOn, isTrue);
    expect(entry.writes, 1);
  });
}
