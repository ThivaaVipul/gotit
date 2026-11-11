import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/release_info.dart';
import 'package:gotit/core/update/update_source.dart';

/// Where the updater stands, for the screen to show.
sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

/// A build made on a PC: it never updates itself.
class UpdateLocalBuild extends UpdateState {
  const UpdateLocalBuild();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate({this.justUpdated = false});

  /// This version arrived through an update since the last start.
  final bool justUpdated;
}

/// A newer release, waiting for a tap (Android).
class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.version);

  final String version;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.version, this.progress);

  final String version;

  /// 0 to 1, or null while the size is unknown.
  final double? progress;
}

class UpdateInstalling extends UpdateState {
  const UpdateInstalling(this.version);

  final String version;
}

/// Android needs "Install unknown apps" allowed for Gotit; tap Update again after.
class UpdateNeedsPermission extends UpdateState {
  const UpdateNeedsPermission(this.version);

  final String version;
}

class UpdateFailed extends UpdateState {
  const UpdateFailed(this.reason);

  final String reason;
}

/// Checks GitHub Releases at start, every [interval] and when the app comes
/// back to the front, downloads the newer release, checks it against
/// SHA256SUMS.txt, and hands it to the [installer].
class Updater extends ValueNotifier<UpdateState> {
  Updater({
    required this.currentVersion,
    required this.source,
    required this.installer,
    required this.downloadDir,
    this.lastSeenVersion,
    this.interval = const Duration(hours: 6),
    this.freshFor = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const UpdateIdle());

  final String currentVersion;
  final UpdateSource source;
  final Installer installer;
  final Future<Directory> Function() downloadDir;

  /// The version that ran last time, if known: a lower one means we just updated.
  final String? lastSeenVersion;
  final Duration interval;

  /// How long a check counts as recent when the app comes back to the front.
  /// GitHub allows 60 unsigned requests an hour from one network.
  final Duration freshFor;
  final DateTime Function() _clock;
  DateTime? _checkedAt;

  ReleaseInfo? _release;
  Timer? _timer;
  bool _busy = false;

  bool get _justUpdated =>
      lastSeenVersion != null && isNewer(currentVersion, lastSeenVersion!);

  /// Checks now and every [interval] after.
  void start() {
    if (isLocalBuild(currentVersion)) {
      value = const UpdateLocalBuild();
      return;
    }
    unawaited(check());
    _timer ??= Timer.periodic(interval, (_) => unawaited(check()));
  }

  /// The app came back to the front. The phone app keeps running in the
  /// background, so opening it doesn't start it again: check here instead,
  /// unless a check was recent.
  Future<void> checkIfStale() async {
    final at = _checkedAt;
    if (at != null && _clock().difference(at) < freshFor) return;
    await check();
  }

  Future<void> check() async {
    if (_busy || isLocalBuild(currentVersion)) return;
    _busy = true;
    _checkedAt = _clock();
    if (value is! UpdateAvailable) value = const UpdateChecking();
    try {
      final release = await source.latest();
      if (release == null ||
          !isNewer(release.version, currentVersion) ||
          installer.assetOf(release) == null ||
          release.checksums == null) {
        value = UpdateUpToDate(justUpdated: _justUpdated);
        return;
      }
      _release = release;
      value = UpdateAvailable(release.version);
    } on Object catch (error) {
      debugPrint('Update check failed: $error');
      value = const UpdateFailed('Couldn\'t check for updates');
    } finally {
      _busy = false;
    }
    if (value is UpdateAvailable && installer.automatic) await install();
  }

  /// Downloads, checks and installs the newer release found by [check].
  Future<void> install() async {
    final release = _release;
    final asset = release == null ? null : installer.assetOf(release);
    if (release == null || asset == null || _busy) return;
    _busy = true;
    try {
      value = UpdateDownloading(release.version, null);
      final sums = await source.fetchText(release.checksums!.url);
      final expected = checksumFor(sums, asset.name);
      if (expected == null) throw StateError('No checksum for ${asset.name}');
      final file = File('${(await downloadDir()).path}/${asset.name}');
      await source.download(
        asset.url,
        file,
        onProgress: (share) =>
            value = UpdateDownloading(release.version, share),
      );
      final actual = sha256.convert(await file.readAsBytes()).toString();
      if (actual != expected) {
        await file.delete();
        throw StateError('Checksum mismatch for ${asset.name}');
      }
      value = UpdateInstalling(release.version);
      final outcome = await installer.install(file);
      value = switch (outcome) {
        InstallOutcome.started => UpdateInstalling(release.version),
        InstallOutcome.needsPermission => UpdateNeedsPermission(
          release.version,
        ),
      };
    } on Object catch (error) {
      debugPrint('Update failed: $error');
      value = const UpdateFailed('The update didn\'t download');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
