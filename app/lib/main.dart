import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gotit/app/app.dart';
import 'package:gotit/app/desktop_shell.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/core/app_version.dart';
import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/core/update/installer.dart';
import 'package:gotit/core/update/release_info.dart';
import 'package:gotit/core/update/update_source.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/core/update/version_memory.dart';
import 'package:path_provider/path_provider.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  DesktopShell? shell;
  if (Platform.isWindows) {
    // A second launch (the Start menu, Send to) shows the running copy and
    // quits.
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      'app-gotit-single-instance',
      bringWindowToFront: false,
      onSecondWindow: (_) => shell?.showWindow(),
    );
    shell = await DesktopShell.start(hidden: args.contains('--hidden'));
  }

  // Inter ships under the SIL Open Font License, which travels with it.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter'], text);
  });

  final version = await currentAppVersion();
  final support = await getApplicationSupportDirectory();
  final settings = await SettingsStore.open(
    File('${support.path}${Platform.pathSeparator}settings.json'),
  );

  StartupEntry? startup;
  if (Platform.isWindows && !isLocalBuild(version)) {
    startup = RunKeyEntry(Platform.resolvedExecutable);
    await applyStartWithWindows(settings, startup);
  }

  final updater = Updater(
    currentVersion: version,
    source: GitHubReleases(),
    installer: Platform.isAndroid
        ? AndroidInstaller()
        : WindowsInstaller(beforeExit: shell?.dispose, inTray: shell?.isInTray),
    downloadDir: getTemporaryDirectory,
    lastSeenVersion: await VersionMemory.swap(version),
  )..start();

  runApp(
    GotitApp(
      services: AppServices(
        version: version,
        updater: updater,
        settings: settings,
        isPc: Platform.isWindows,
        startup: startup,
        windowsName: Platform.isWindows ? Platform.localHostname : '',
      ),
    ),
  );
}
