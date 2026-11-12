import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gotit/app/app.dart';
import 'package:gotit/app/desktop_shell.dart';
import 'package:gotit/app/pc_sends.dart';
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
import 'package:gotit/core/platform/pc_files.dart';
import 'package:gotit/core/platform/pc_notices.dart';
import 'package:gotit/core/platform/phone_downloads.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/platform/share_target.dart';
import 'package:gotit/core/platform/sharing_controls.dart';
import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/notice_keeper.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/core/transfer/folder_store.dart';
import 'package:gotit/core/transfer/pc_sender.dart';
import 'package:gotit/core/transfer/transfers.dart';
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
  PcSends? pcSends;
  // Send to's files: the ones Gotit started with, and any a second launch
  // handed over before sending was ready.
  final toSend = <List<String>>[];
  if (Platform.isWindows) {
    final sendAtStart = await sendRequest(args);
    if (sendAtStart != null) toSend.add(sendAtStart);
    // A second launch hands its arguments to the running copy and quits:
    // Send to's files are sent, and anything else (the Start menu) shows the
    // window.
    final handOver = await handOverArgs(args, _sendTemp);
    await WindowsSingleInstance.ensureSingleInstance(
      handOver,
      'app-gotit-single-instance',
      bringWindowToFront: false,
      onSecondWindow: (second) async {
        final paths = await sendRequest(second);
        if (paths == null) {
          await shell?.showWindow();
        } else if (pcSends case final sends?) {
          await sends.fromTray(paths);
        } else {
          toSend.add(paths);
        }
      },
    );
    // This is the running copy: a list written to hand over isn't needed.
    if (!identical(handOver, args)) {
      unawaited(_deleteQuietly(File(handOver.last)));
    }
    await _clearSendTemp();
    shell = await DesktopShell.start(
      hidden: args.contains('--hidden') || sendAtStart != null,
    );
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
  SharingSwitch? sharing;
  Transfers? transfers;
  PcFiles? pcFiles;
  GlobalKey<NavigatorState>? navigator;
  // The switch both devices share, kept across restarts.
  SharingSwitch sharingOver(SharingLink link) => SharingSwitch(
    initial: settings.value.sharing ?? SharingState.initial,
    deviceId: identity.id,
    link: link,
    save: (state) =>
        settings.save(settings.value.copyWith(sharing: () => state)),
  )..start();
  if (Platform.isWindows) {
    pcLink = PcLink(
      identity: identity,
      name: () => effectivePcName(settings.value, windowsName),
      phone: settings.value.peer,
      savePhone: savePeer,
      // A phone asking to pair brings the window forward for Accept.
      onRequest: (_) => shell?.showWindow(),
    );
    final pcSharing = sharingOver(pcLink);
    sharing = pcSharing;
    // The tray's Sharing item, and its greyed icon while off.
    final tray = shell;
    if (tray != null) {
      tray.onSharing = pcSharing.set;
      void showSharing() => unawaited(tray.showSharing(on: pcSharing.on));
      pcSharing.addListener(showSharing);
      showSharing();
    }
    await _advertise(pcLink, identity, settings, windowsName);
    // Copies cross both ways while sharing is on; one that reaches the phone
    // flashes the tray.
    final clipboard = ChannelClipboard();
    ClipBridge(
      link: pcLink,
      clipboard: clipboard,
      sharing: () => pcSharing.on,
      onSent: (_) => shell?.flashSent(),
    ).start();
    // Files from the phone: Downloads\Gotit, then on the clipboard ready to
    // paste, with a toast. Refused while sharing is off.
    final notices = PcNotices();
    unawaited(notices.setup(localBuild: isLocalBuild(version)));
    final link = pcLink;
    final pcTransfers = Transfers(
      link: link,
      store: GatedStore(
        FolderStore(() async {
          final downloads = await getDownloadsDirectory();
          return Directory(
            '${downloads?.path ?? support.path}${Platform.pathSeparator}Gotit',
          );
        }),
        open: () => pcSharing.on,
      ),
      onBatch: (files) {
        final picture = files.length == 1 && files.single.isImage
            ? files.single.location
            : null;
        unawaited(
          clipboard.writeFiles([
            for (final file in files) file.location,
          ], picture: picture),
        );
        unawaited(
          notices.received(files, from: link.state.phone?.name ?? 'your phone'),
        );
      },
    )..start();
    transfers = pcTransfers;
    // Files to the phone: dropped on the window, Send to, or Ctrl+F2.
    final appNavigator = navigator = GlobalKey<NavigatorState>();
    final files = pcFiles = PcFiles();
    final sends = PcSends(
      sender: PcSender(
        link: link,
        transfers: pcTransfers,
        phoneName: () => link.state.phone?.name,
        sharingOn: () => pcSharing.on,
        turnSharingOn: () => pcSharing.set(on: true),
        temp: _sendTemp,
      ),
      notices: notices,
      navigator: appNavigator,
      phoneName: () => link.state.phone?.name ?? 'your phone',
      shell: shell,
    );
    files
      ..onDropped = ((paths) => unawaited(sends.dropped(paths)))
      ..onHotkey = ((paths) => unawaited(sends.fromTray(paths, hotkey: true)));
    unawaited(files.start());
    pcSends = sends;
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
    final phoneSharing = sharingOver(phoneLink);
    sharing = phoneSharing;
    // The tile, the notification's buttons and the copy watcher follow it.
    PhoneSharingControls(
      sharing: phoneSharing,
      link: phoneLink,
      settings: settings,
    ).start();
    unawaited(_startLooking(pcFinder, phoneLink));
    // The ongoing notification keeps the link running while paired, and
    // says "Sent to <PC>" after a copy crossed.
    final link = phoneLink;
    final setup = ChannelPhoneSetup();
    phoneSetup = setup;
    // Files: sent from the share sheet; from the PC they go to
    // Download/Gotit, with a notice. Refused while sharing is off.
    final downloads = PhoneDownloads();
    final phoneTransfers = Transfers(
      link: link,
      store: GatedStore(downloads, open: () => phoneSharing.on),
      onBatch: (files) => unawaited(
        downloads.arrived(files, from: link.state.pc?.name ?? 'your PC'),
      ),
    )..start();
    transfers = phoneTransfers;
    final notice = NoticeKeeper(
      states: link.states,
      current: () => link.state,
      notice: const ChannelLinkNotice(),
      watcher: setup.watcherChanges,
      sharing: phoneSharing,
      transfers: phoneTransfers,
    )..start();
    final bridge = ClipBridge(
      link: phoneLink,
      clipboard: ChannelClipboard(),
      sharing: () => phoneSharing.on,
      onSent: (_) => notice.sent(),
    )..start();
    // Share > Gotit: files, and links or text.
    PhoneShareTarget(
      link: link,
      transfers: phoneTransfers,
      sharing: phoneSharing,
      bridge: bridge,
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
        sharing: sharing,
        transfers: transfers,
        pcFiles: pcFiles,
        navigator: navigator,
      ),
    ),
  );

  // Send to's files, now that the window can ask if it must.
  if (pcSends case final sends?) {
    final waiting = List.of(toSend);
    toSend.clear();
    for (final paths in waiting) {
      unawaited(sends.fromTray(paths));
    }
  }
}

/// Where the PC zips folders to send, and keeps a long Send to list a second
/// launch hands over.
Future<Directory> _sendTemp() async => Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}gotit-send',
);

/// Clears zips a send left behind (Gotit was closed while sending) and
/// hand-over lists nobody read.
Future<void> _clearSendTemp() async {
  final dir = await _sendTemp();
  if (!dir.existsSync()) return;
  final old = DateTime.now().subtract(const Duration(minutes: 10));
  try {
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('zip-') ||
          (name.startsWith('send-') &&
              entry.statSync().modified.isBefore(old))) {
        await entry.delete(recursive: true);
      }
    }
  } on FileSystemException {
    // Tried again at the next start.
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // Gone already.
  }
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
