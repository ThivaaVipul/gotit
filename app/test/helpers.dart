import 'dart:io';

import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/release_info.dart';
import 'package:gotit/core/update/update_source.dart';
import 'package:gotit/core/update/updater.dart';

/// A start-with-Windows switch that remembers instead of touching the registry.
class FakeEntry implements StartupEntry {
  @override
  bool isOn = false;
  int writes = 0;

  @override
  void turnOn() {
    isOn = true;
    writes++;
  }

  @override
  void turnOff() {
    isOn = false;
    writes++;
  }
}

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

/// An updater that never reaches the network, showing [state].
Updater noUpdates(UpdateState state) => Updater(
  currentVersion: '0.1.0',
  source: _NoSource(),
  installer: _NoInstaller(),
  downloadDir: () async => Directory.systemTemp,
)..value = state;
