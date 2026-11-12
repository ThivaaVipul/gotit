import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Files the Windows runner hands to Gotit: dropped on the window, or copied
/// in Explorer when Ctrl+F2 was pressed. It also says while files hover
/// over the window, and whether Ctrl+F2 is Gotit's (another app may hold
/// it).
class PcFiles {
  PcFiles() {
    _channel.setMethodCallHandler((call) async {
      final paths = _paths(call.arguments);
      switch (call.method) {
        case 'dragging':
          dragging.value = call.arguments == true;
        case 'dropped':
          dragging.value = false;
          onDropped?.call(paths);
        case 'hotkey':
          onHotkey?.call(paths);
      }
    });
  }

  static const _channel = MethodChannel('app.gotit/files');

  /// Files hovering over the window, about to be dropped.
  final dragging = ValueNotifier<bool>(false);

  /// Whether Ctrl+F2 is Gotit's; null until the runner has said.
  final hotkey = ValueNotifier<bool?>(null);

  /// Files dropped on the window.
  void Function(List<String> paths)? onDropped;

  /// Ctrl+F2, with the files copied in Explorer (none when nothing was).
  void Function(List<String> paths)? onHotkey;

  /// Asks the runner whether it holds Ctrl+F2.
  Future<void> start() async {
    try {
      hotkey.value = await _channel.invokeMethod<bool>('hotkey');
    } on PlatformException {
      // Unknown: say nothing about it.
    } on MissingPluginException {
      // Unknown: say nothing about it.
    }
  }

  static List<String> _paths(Object? arguments) => [
    if (arguments is List)
      for (final path in arguments)
        if (path is String && path.isNotEmpty) path,
  ];
}
