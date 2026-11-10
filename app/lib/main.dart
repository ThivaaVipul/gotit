import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gotit/app/app.dart';
import 'package:gotit/core/app_version.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/update_source.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/core/update/version_memory.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inter ships under the SIL Open Font License, which travels with it.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter'], text);
  });
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
