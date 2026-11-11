import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gotit/app/app.dart';
import 'package:gotit/app/desktop_shell.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/core/app_version.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/link/discovery.dart';
import 'package:gotit/core/link/identity.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/clipboard.dart';
import 'package:gotit/core/platform/device.dart';
import 'package:gotit/core/platform/mdns.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/state/notice_keeper.dart';
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

  final identity = await IdentityStore(deviceSecrets(support)).loadOrCreate();
  Future<void> savePeer(Peer? peer) =>
      settings.save(settings.value.copyWith(peer: () => peer));

  final windowsName = Platform.isWindows ? Platform.localHostname : '';
  PcLink? pcLink;
  PhoneLink? phoneLink;
  PcFinder? finder;
  PhoneSetup? phoneSetup;
  if (Platform.isWindows) {
    pcLink = PcLink(
      identity: identity,
      name: () => effectivePcName(settings.value, windowsName),
      phone: settings.value.peer,
      savePhone: savePeer,
      // A phone asking to pair brings the window forward for Accept.
      onRequest: (_) => shell?.showWindow(),
    );
    await _advertise(pcLink, identity, settings, windowsName);
    // Copies cross both ways; one that reaches the phone flashes the tray.
    ClipBridge(
      link: pcLink,
      clipboard: ChannelClipboard(),
      onSent: (_) => shell?.flashSent(),
    ).start();
  } else {
    final pcFinder = BonsoirPcFinder();
    finder = pcFinder;
    phoneLink = PhoneLink(
      identity: identity,
      name: await phoneName(),
      pc: settings.value.peer,
      savePc: savePeer,
      locate: (pcId) async => endpointsOf(pcFinder, pcId),
    );
    unawaited(_startLooking(pcFinder, phoneLink));
    // The ongoing notification keeps the link running while paired, and
    // says "Sent to <PC>" after a copy crossed.
    final link = phoneLink;
    final setup = ChannelPhoneSetup();
    phoneSetup = setup;
    final notice = NoticeKeeper(
      states: link.states,
      current: () => link.state,
      notice: const ChannelLinkNotice(),
      watcher: setup.watcherChanges,
    )..start();
    ClipBridge(
      link: phoneLink,
      clipboard: ChannelClipboard(),
      onSent: (_) => notice.sent(),
    ).start();
  }

  runApp(
    GotitApp(
      services: AppServices(
        version: version,
        updater: updater,
        settings: settings,
        isPc: Platform.isWindows,
        startup: startup,
        windowsName: windowsName,
        pcLink: pcLink,
        phoneLink: phoneLink,
        finder: finder,
        phoneSetup: phoneSetup,
      ),
    ),
  );
}

/// Starts the PC's listener and its mDNS advertisement, and keeps both
/// current when the PC is renamed.
Future<void> _advertise(
  PcLink link,
  Identity identity,
  SettingsStore settings,
  String windowsName,
) async {
  try {
    await link.start();
  } on SocketException {
    // Nothing can reach this PC; the screens still work.
    return;
  }
  final beacon = BonsoirPcBeacon();
  var name = effectivePcName(settings.value, windowsName);
  Future<void> announce() async {
    try {
      await beacon.start(id: identity.id, name: name, port: link.port);
    } on Object {
      // mDNS is unavailable: QR pairing and remembered addresses still work.
    }
  }

  await announce();
  settings.addListener(() {
    final renamed = effectivePcName(settings.value, windowsName);
    if (renamed == name) return;
    name = renamed;
    link.renamed();
    unawaited(announce());
  });
}

/// The phone looks for PCs while it runs: to list them before pairing, and
/// to find the paired PC again if its address changes.
Future<void> _startLooking(PcFinder finder, PhoneLink link) async {
  try {
    await finder.start();
  } on Object {
    // mDNS is unavailable: the remembered address and QR pairing still work.
  }
  link.start();
  // When the paired PC shows up on the network, try it at once.
  finder.changes.listen((pcs) {
    final pc = link.state.pc;
    if (pc != null && pcs.any((found) => found.id == pc.id)) link.retryNow();
  });
}
