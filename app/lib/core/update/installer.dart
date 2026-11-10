import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gotit/core/update/release_info.dart';

enum InstallOutcome {
  /// Android's install prompt is showing, or the Windows setup is running.
  started,

  /// Android needs "Install unknown apps" allowed for Gotit first; its settings page is open.
  needsPermission,
}

/// Installs a downloaded release the way the platform allows.
abstract interface class Installer {
  /// The release file this platform installs.
  ReleaseAsset? assetOf(ReleaseInfo release);

  /// Whether to install without asking (Windows) or wait for a tap (Android).
  bool get automatic;

  Future<InstallOutcome> install(File file);
}

/// Hands the APK to Android's own installer, through MainActivity.
class AndroidInstaller implements Installer {
  static const _channel = MethodChannel('app.gotit/updates');

  @override
  ReleaseAsset? assetOf(ReleaseInfo release) => release.apk;

  @override
  bool get automatic => false;

  @override
  Future<InstallOutcome> install(File file) async {
    final allowed = await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!allowed) {
      await _channel.invokeMethod<void>('openInstallSettings');
      return InstallOutcome.needsPermission;
    }
    await _channel.invokeMethod<void>('install', {'path': file.path});
    return InstallOutcome.started;
  }
}

/// Runs the new setup silently and steps aside: the setup closes and restarts Gotit.
class WindowsInstaller implements Installer {
  WindowsInstaller({this.beforeExit, this.inTray});

  /// Runs just before the app steps aside for the setup, such as removing the
  /// tray icon.
  final Future<void> Function()? beforeExit;

  /// Whether the window is hidden in the tray. If so, the setup starts the
  /// new version in the tray too, instead of opening its window.
  final Future<bool> Function()? inTray;

  @override
  ReleaseAsset? assetOf(ReleaseInfo release) => release.setup;

  @override
  bool get automatic => true;

  @override
  Future<InstallOutcome> install(File file) async {
    final hidden = await inTray?.call() ?? false;
    await Process.start(file.path, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      // Read by the setup's [Run] entry: start the new version in the tray.
      if (hidden) '/RUNARGS=--hidden',
    ], mode: ProcessStartMode.detached);
    // Give the setup a moment to start, then let it replace our files.
    Future<void>.delayed(const Duration(seconds: 1), () async {
      await beforeExit?.call();
      exit(0);
    });
    return InstallOutcome.started;
  }
}
