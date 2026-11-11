import 'package:gotit/core/link/discovery.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/platform/start_with_windows.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/core/update/updater.dart';

/// What the screens need from the rest of the app, made once in main.
class AppServices {
  const AppServices({
    required this.version,
    required this.updater,
    required this.settings,
    required this.isPc,
    this.startup,
    this.windowsName = '',
    this.pcLink,
    this.phoneLink,
    this.finder,
    this.phoneSetup,
    this.sharing,
  });

  final String version;
  final Updater updater;
  final SettingsStore settings;

  /// Running on the PC (Windows), not the phone.
  final bool isPc;

  /// Starting with Windows. Empty on the phone and in local builds, which
  /// never touch it.
  final StartupEntry? startup;

  /// The PC's Windows name, the default name the phone shows.
  final String windowsName;

  /// The PC's side of the link (the PC only).
  final PcLink? pcLink;

  /// The phone's side of the link (the phone only).
  final PhoneLink? phoneLink;

  /// Finds PCs on the network (the phone only).
  final PcFinder? finder;

  /// The setup checklist's side on the phone (the phone only).
  final PhoneSetup? phoneSetup;

  /// The shared sharing switch, once paired devices can use it.
  final SharingSwitch? sharing;

  /// The PC's name as the phone shows it.
  String get pcName => effectivePcName(settings.value, windowsName);
}

/// The chosen PC name, or the Windows name when none is chosen.
String effectivePcName(Settings settings, String windowsName) {
  final chosen = settings.pcName?.trim();
  return chosen == null || chosen.isEmpty ? windowsName : chosen;
}
