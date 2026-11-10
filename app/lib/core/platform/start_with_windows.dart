import 'package:gotit/core/state/settings.dart';
import 'package:win32_registry/win32_registry.dart';

/// The switch that makes Gotit start when you sign in to Windows.
abstract interface class StartupEntry {
  bool get isOn;
  void turnOn();
  void turnOff();
}

/// The per-user Run key, the same place Task Manager's Startup apps lists.
/// No admin needed. The uninstaller removes the value.
class RunKeyEntry implements StartupEntry {
  RunKeyEntry(this.executable);

  /// The installed gotit.exe. It starts hidden in the tray.
  final String executable;

  static const _path = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _name = 'Gotit';

  @override
  bool get isOn {
    final key = CURRENT_USER.create(_path);
    try {
      return key.getString(_name) != null;
    } finally {
      key.close();
    }
  }

  @override
  void turnOn() {
    final key = CURRENT_USER.create(_path);
    try {
      key.setValue(_name, RegistryValue.string('"$executable" --hidden'));
    } finally {
      key.close();
    }
  }

  @override
  void turnOff() {
    final key = CURRENT_USER.create(_path);
    try {
      if (key.getString(_name) != null) key.removeValue(_name);
    } finally {
      key.close();
    }
  }
}

/// Brings the Run key in line with the setting, at every launch of an
/// installed copy. The first launch turns it on, which is the default; after
/// that, whatever the user chose sticks. Rewriting the value also keeps the
/// path current.
Future<void> applyStartWithWindows(
  SettingsStore settings,
  StartupEntry entry,
) async {
  final wanted = settings.value.startWithWindows ?? true;
  if (settings.value.startWithWindows == null) {
    await settings.save(settings.value.copyWith(startWithWindows: () => true));
  }
  wanted ? entry.turnOn() : entry.turnOff();
}
