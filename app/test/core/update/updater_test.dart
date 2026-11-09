import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/release_info.dart';
import 'package:gotit/core/update/update_source.dart';
import 'package:gotit/core/update/updater.dart';

const _bytes = [1, 2, 3, 4];
final _goodSum = sha256.convert(_bytes).toString();

ReleaseInfo release(String version, {bool withApk = true}) => ReleaseInfo(
  version: version,
  apk: withApk
      ? ReleaseAsset(
          'gotit-$version.apk',
          Uri.parse('https://example.com/gotit-$version.apk'),
          4,
        )
      : null,
  checksums: ReleaseAsset(
    'SHA256SUMS.txt',
    Uri.parse('https://example.com/SHA256SUMS.txt'),
    100,
  ),
);

class FakeSource implements UpdateSource {
  FakeSource({this.latestRelease, String? sums, this.fail = false})
    : sums = sums ?? '$_goodSum  gotit-0.2.0.apk\n';

  final ReleaseInfo? latestRelease;
  final String sums;
  final bool fail;
  int latestCalls = 0;

  @override
  Future<ReleaseInfo?> latest() async {
    latestCalls++;
    if (fail) throw const HttpException('offline');
    return latestRelease;
  }

  @override
  Future<String> fetchText(Uri url) async => sums;

  @override
  Future<void> download(
    Uri url,
    File to, {
    void Function(double)? onProgress,
  }) async {
    await to.writeAsBytes(_bytes);
    onProgress?.call(1);
  }
}

class FakeInstaller implements Installer {
  FakeInstaller({
    this.automatic = false,
    this.outcome = InstallOutcome.started,
  });

  @override
  final bool automatic;
  final InstallOutcome outcome;
  final installed = <String>[];

  @override
  ReleaseAsset? assetOf(ReleaseInfo release) => release.apk;

  @override
  Future<InstallOutcome> install(File file) async {
    installed.add(file.uri.pathSegments.last);
    return outcome;
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('gotit_update_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Updater updater({
    required String current,
    required FakeSource source,
    FakeInstaller? installer,
    String? lastSeen,
  }) => Updater(
    currentVersion: current,
    source: source,
    installer: installer ?? FakeInstaller(),
    downloadDir: () async => dir,
    lastSeenVersion: lastSeen,
  );

  test('a local build never checks', () {
    final source = FakeSource(latestRelease: release('0.2.0'));
    final subject = updater(current: '0.0.0', source: source)..start();
    expect(subject.value, isA<UpdateLocalBuild>());
    expect(source.latestCalls, 0);
    subject.dispose();
  });

  test('up to date when the latest release is not newer', () async {
    final subject = updater(
      current: '0.2.0',
      source: FakeSource(latestRelease: release('0.2.0')),
    );
    await subject.check();
    expect(subject.value, isA<UpdateUpToDate>());
    expect((subject.value as UpdateUpToDate).justUpdated, isFalse);
  });

  test('says it just updated when the last run was older', () async {
    final subject = updater(
      current: '0.2.0',
      lastSeen: '0.1.0',
      source: FakeSource(latestRelease: release('0.2.0')),
    );
    await subject.check();
    expect((subject.value as UpdateUpToDate).justUpdated, isTrue);
  });

  test('offers a newer release and installs it after a tap', () async {
    final installer = FakeInstaller();
    final subject = updater(
      current: '0.1.0',
      source: FakeSource(latestRelease: release('0.2.0')),
      installer: installer,
    );
    await subject.check();
    expect(subject.value, isA<UpdateAvailable>());
    expect(installer.installed, isEmpty);

    await subject.install();
    expect(installer.installed, ['gotit-0.2.0.apk']);
    expect(subject.value, isA<UpdateInstalling>());
  });

  test('installs by itself where updates are automatic', () async {
    final installer = FakeInstaller(automatic: true);
    final subject = updater(
      current: '0.1.0',
      source: FakeSource(latestRelease: release('0.2.0')),
      installer: installer,
    );
    await subject.check();
    expect(installer.installed, ['gotit-0.2.0.apk']);
  });

  test('refuses a download whose checksum does not match', () async {
    final installer = FakeInstaller(automatic: true);
    final subject = updater(
      current: '0.1.0',
      source: FakeSource(
        latestRelease: release('0.2.0'),
        sums: '${'0' * 64}  gotit-0.2.0.apk\n',
      ),
      installer: installer,
    );
    await subject.check();
    expect(installer.installed, isEmpty);
    expect(subject.value, isA<UpdateFailed>());
    expect(File('${dir.path}/gotit-0.2.0.apk').existsSync(), isFalse);
  });

  test('asks for the install permission when Android needs it', () async {
    final subject = updater(
      current: '0.1.0',
      source: FakeSource(latestRelease: release('0.2.0')),
      installer: FakeInstaller(outcome: InstallOutcome.needsPermission),
    );
    await subject.check();
    await subject.install();
    expect(subject.value, isA<UpdateNeedsPermission>());
  });

  test('skips a release without this platform\'s file', () async {
    final subject = updater(
      current: '0.1.0',
      source: FakeSource(latestRelease: release('0.2.0', withApk: false)),
    );
    await subject.check();
    expect(subject.value, isA<UpdateUpToDate>());
  });

  test('a failed check says so', () async {
    final subject = updater(current: '0.1.0', source: FakeSource(fail: true));
    await subject.check();
    expect(subject.value, isA<UpdateFailed>());
  });
}
