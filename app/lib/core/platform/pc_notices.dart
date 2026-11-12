import 'dart:async';
import 'dart:io';

import 'package:gotit/core/platform/shell.dart';
import 'package:gotit/core/transfer/transfers.dart';
import 'package:local_notifier/local_notifier.dart';

/// The PC's toasts: files from the phone have arrived, with Open and Show in
/// folder.
///
/// Windows shows a desktop app's toasts only through a Start menu shortcut
/// carrying its app ID. The installer's shortcut carries "Gotit", the name
/// used here; a local build only stamps that ID on a shortcut that already
/// exists, and never makes one.
class PcNotices {
  bool _ready = false;

  Future<void> setup({required bool localBuild}) async {
    final appData = Platform.environment['APPDATA'];
    final shortcut = appData == null
        ? null
        : File('$appData\\Microsoft\\Windows\\Start Menu\\Programs\\Gotit.lnk');
    final mayTouch = !localBuild || (shortcut?.existsSync() ?? false);
    try {
      await localNotifier.setup(
        appName: 'Gotit',
        shortcutPolicy: mayTouch
            ? ShortcutPolicy.requireCreate
            : ShortcutPolicy.ignore,
      );
      _ready = true;
    } on Object {
      // No toasts; the files still arrive and go on the clipboard.
    }
  }

  /// [files] arrived from [from].
  Future<void> received(
    List<ReceivedFile> files, {
    required String from,
  }) async {
    if (!_ready || files.isEmpty) return;
    final one = files.length == 1;
    final notice = LocalNotification(
      title: 'From $from',
      body: one
          ? '${files.single.name} - on the clipboard'
          : '${files.length} files - on the clipboard',
      // One file: Open and Show in folder. Several: Show in folder.
      actions: [
        if (one) LocalNotificationAction(text: 'Open'),
        LocalNotificationAction(text: 'Show in folder'),
      ],
    );
    void open() => one
        ? openPath(files.single.location)
        : revealPath(files.first.location);
    notice
      ..onClick = open
      ..onClickAction = (index) {
        if (one && index == 0) {
          openPath(files.single.location);
        } else {
          revealPath(files.first.location);
        }
      };
    try {
      await notice.show();
    } on Object {
      // A toast that can't show changes nothing else.
    }
  }
}
