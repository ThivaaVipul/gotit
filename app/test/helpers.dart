import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

/// A tiny PNG header saying [width] x [height], plus [extra] bytes to make
/// images of different sizes and digests.
Uint8List png(int width, int height, {int extra = 0, int seed = 1}) {
  final bytes = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  final size = ByteData(8)
    ..setUint32(0, width)
    ..setUint32(4, height);
  bytes
    ..add(size.buffer.asUint8List())
    ..add(List.filled(5, 0));
  final random = Random(seed);
  bytes.add(List.generate(extra, (_) => random.nextInt(256)));
  return bytes.toBytes();
}
