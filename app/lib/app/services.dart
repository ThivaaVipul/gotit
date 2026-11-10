import 'package:gotit/core/platform/start_with_windows.dart';
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
  });

  final String version;
  final Updater updater;
  final SettingsStore settings;

  /// Starting with Windows. Empty on the phone and in local builds, which
  /// never touch it.
  final StartupEntry? startup;

  /// The PC's Windows name, the default name the phone shows.
  final String windowsName;

  /// Running on the PC (Windows), not the phone.
  final bool isPc;

  /// The PC's name as the phone shows it.
  String get pcName {
    final chosen = settings.value.pcName?.trim();
    return chosen == null || chosen.isEmpty ? windowsName : chosen;
  }
}
