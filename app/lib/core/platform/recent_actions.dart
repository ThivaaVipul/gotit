import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gotit/core/platform/shell.dart';
import 'package:gotit/core/recent/recent.dart';
import 'package:gotit/core/recent/recent_actions.dart';
import 'package:gotit/core/recent/recent_keeper.dart';

/// The recent list's actions on the PC: Explorer and each file's usual app.
class PcRecentActions implements RecentActions {
  PcRecentActions(this.keeper);

  final RecentKeeper keeper;

  @override
  Future<bool> copy(RecentItem item) => keeper.copy(item);

  @override
  void openLink(String url) => openPath(url);

  @override
  void open(RecentItem item) {
    final target = item.kind == RecentKind.image
        ? item.image
        : item.files.firstOrNull?.location;
    if (target != null) openPath(target);
  }

  @override
  void reveal(RecentItem item) {
    final target = item.kind == RecentKind.image
        ? item.image
        : item.files.firstOrNull?.location;
    if (target != null) revealPath(target);
  }

  @override
  void openFolder(RecentItem item) {
    final first = item.files.firstOrNull?.location;
    if (first != null) openPath(File(first).parent.path);
  }

  @override
  void share(RecentItem item) {}
}

/// The recent list's actions on the phone, through Kotlin: the browser,
/// each file's usual app, Files at `Download/Gotit`, and the share sheet.
class PhoneRecentActions implements RecentActions {
  PhoneRecentActions(this.keeper);

  final RecentKeeper keeper;

  static const _channel = MethodChannel('app.gotit/received');

  @override
  Future<bool> copy(RecentItem item) => keeper.copy(item);

  @override
  void openLink(String url) => _call('openLink', {'url': url});

  @override
  void open(RecentItem item) {
    final uri = item.files.firstOrNull?.location;
    if (uri != null) _call('open', {'uri': uri});
  }

  @override
  void reveal(RecentItem item) => openFolder(item);

  @override
  void openFolder(RecentItem item) => _call('openFolder', const {});

  @override
  void share(RecentItem item) {
    if (item.kind == RecentKind.image) {
      final path = item.image;
      if (path != null) _call('shareImage', {'path': path});
      return;
    }
    final uris = [for (final file in item.files) ?file.location];
    if (uris.isNotEmpty) _call('share', {'uris': uris});
  }

  void _call(String method, Map<String, Object?> args) =>
      unawaited(_quietly(() => _channel.invokeMethod<void>(method, args)));
}

/// A link that arrived, shown quietly with Open: a silent toast on the PC
/// (the runner), a silent notification on the phone (Kotlin). The newest
/// replaces the last, and it goes by itself after 5 minutes.
Future<void> showLinkNotice({required String from, required String url}) =>
    _quietly(
      () =>
          (Platform.isWindows
                  ? const MethodChannel('app.gotit/notices')
                  : const MethodChannel('app.gotit/received'))
              .invokeMethod<void>('link', {
                'title': 'Link from $from',
                'text': shownLink(url),
                'url': url,
              }),
    );

Future<void> _quietly(Future<void> Function() call) async {
  try {
    await call();
  } on PlatformException {
    // Nothing opened; the list still has it.
  } on MissingPluginException {
    // The same.
  }
}
