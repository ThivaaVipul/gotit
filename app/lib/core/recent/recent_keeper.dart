import 'dart:async';
import 'dart:io';

import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/recent/recent.dart';

/// Keeps the recent list as copies cross, puts items back on this device's
/// clipboard, and wipes a sensitive copy Gotit put on the clipboard when its
/// minute is up, unless something replaced it since.
class RecentKeeper {
  RecentKeeper({
    required this.list,
    required this.clipboard,
    required this.copyHere,
    this.onLink,
  });

  final RecentList list;
  final DeviceClipboard clipboard;

  /// Puts a clip on this device's clipboard without it crossing
  /// ([ClipBridge.copyHere]), giving back the mark for wiping it.
  final Future<Object?> Function(Clip clip) copyHere;

  /// A link arrived from the other device (a sensitive copy never counts).
  final void Function(String url)? onLink;

  final _wipes = <String, Timer>{};

  /// A copy made here reached the other device.
  Future<void> sent(Clip clip) async {
    await list.addClip(clip, RecentWay.sent);
  }

  /// A copy from the other device is on this clipboard; [mark] is what the
  /// clipboard gave back for wiping it.
  Future<void> arrived(Clip clip, Object? mark) async {
    final item = await list.addClip(clip, RecentWay.received);
    if (item == null) return;
    if (item.sensitive && mark != null) _wipeLater(item.id, mark);
    if (item.kind == RecentKind.link) onLink?.call(item.text);
  }

  /// Puts [item] back on this device's clipboard, and moves it to the top.
  /// False when it can't (files, or an image that is gone).
  Future<bool> copy(RecentItem item) async {
    final clip = await clipOf(item);
    if (clip == null) return false;
    final Object? mark;
    try {
      mark = await copyHere(clip);
    } on Object {
      return false;
    }
    if (item.sensitive && mark != null) _wipeLater(item.id, mark);
    list.copiedAgain(item.id);
    return true;
  }

  void dispose() {
    for (final timer in _wipes.values) {
      timer.cancel();
    }
    _wipes.clear();
  }

  /// What [item] puts back on the clipboard: its text or link, or its image.
  static Future<Clip?> clipOf(RecentItem item) async {
    switch (item.kind) {
      case RecentKind.text || RecentKind.link:
        return Clip(text: item.text, sensitive: item.sensitive);
      case RecentKind.image:
        final path = item.image;
        if (path == null) return null;
        try {
          return Clip(image: await File(path).readAsBytes());
        } on FileSystemException {
          return null;
        }
      case RecentKind.files:
        return null;
    }
  }

  /// When the sensitive item [id] leaves the list, wipes what the write that
  /// gave [mark] put on the clipboard, if it is still there. A later copy of
  /// the same item replaces the earlier mark.
  void _wipeLater(String id, Object mark) {
    final deadline = list.deadlineOf(id);
    if (deadline == null) return;
    _wipes.remove(id)?.cancel();
    final wait = deadline.difference(DateTime.now());
    _wipes[id] = Timer(wait.isNegative ? Duration.zero : wait, () {
      _wipes.remove(id);
      unawaited(clipboard.wipe(mark));
    });
  }
}
