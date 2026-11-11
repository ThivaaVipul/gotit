import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/sharing/sharing.dart';

/// What the user chose. Empty fields mean "never set": the defaults apply.
@immutable
class Settings {
  const Settings({this.pcName, this.startWithWindows, this.peer, this.sharing});

  /// The PC's name as the phone shows it. Empty means the Windows name.
  final String? pcName;

  /// Whether Gotit starts with Windows. Empty means never decided, and the
  /// default (on) applies the first time an installed copy runs.
  final bool? startWithWindows;

  /// The paired device: the phone on the PC, the PC on the phone.
  final Peer? peer;

  /// The sharing switch as last known. Empty means on, never changed.
  final SharingState? sharing;

  Settings copyWith({
    ValueGetter<String?>? pcName,
    ValueGetter<bool?>? startWithWindows,
    ValueGetter<Peer?>? peer,
    ValueGetter<SharingState?>? sharing,
  }) => Settings(
    pcName: pcName != null ? pcName() : this.pcName,
    startWithWindows: startWithWindows != null
        ? startWithWindows()
        : this.startWithWindows,
    peer: peer != null ? peer() : this.peer,
    sharing: sharing != null ? sharing() : this.sharing,
  );

  Map<String, Object?> toJson() => {
    if (pcName != null) 'pcName': pcName,
    if (startWithWindows != null) 'startWithWindows': startWithWindows,
    if (peer != null) 'peer': peer!.toJson(),
    if (sharing != null) 'sharing': sharing!.toJson(),
  };

  factory Settings.fromJson(Map<String, Object?> json) => Settings(
    pcName: json['pcName'] is String ? json['pcName'] as String : null,
    startWithWindows: json['startWithWindows'] is bool
        ? json['startWithWindows'] as bool
        : null,
    peer: _peerFrom(json['peer']),
    sharing: SharingState.fromJson(json['sharing']),
  );

  static Peer? _peerFrom(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      return Peer.fromJson(json);
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.pcName == pcName &&
      other.startWithWindows == startWithWindows &&
      other.peer == peer &&
      other.sharing == sharing;

  @override
  int get hashCode => Object.hash(pcName, startWithWindows, peer, sharing);
}

/// Keeps [Settings] in a small JSON file and tells listeners when they change.
class SettingsStore extends ValueNotifier<Settings> {
  SettingsStore._(this._file, super.value);

  final File _file;

  /// Opens the store at [file]. A missing or unreadable file gives defaults.
  static Future<SettingsStore> open(File file) async {
    var settings = const Settings();
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, Object?>) settings = Settings.fromJson(json);
      }
    } on FormatException {
      // A damaged file: start again from the defaults.
    } on FileSystemException {
      // Unreadable: the same.
    }
    return SettingsStore._(file, settings);
  }

  /// Saves [next] and tells listeners. Writes a temporary file first, so a
  /// crash mid-write can't leave a half-written one behind.
  Future<void> save(Settings next) async {
    value = next;
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(next.toJson()), flush: true);
    await temp.rename(_file.path);
  }
}
