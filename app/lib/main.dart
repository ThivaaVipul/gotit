import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gotit/app/app.dart';
import 'package:gotit/core/app_version.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/update_source.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/core/update/version_memory.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final version = await currentAppVersion();
  final updater = Updater(
    currentVersion: version,
    source: GitHubReleases(),
    installer: Platform.isAndroid ? AndroidInstaller() : WindowsInstaller(),
    downloadDir: getTemporaryDirectory,
    lastSeenVersion: await VersionMemory.swap(version),
  )..start();
  runApp(GotitApp(version: version, updater: updater));
}
