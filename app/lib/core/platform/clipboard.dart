import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';

/// The clipboard through the platform side: the Windows runner on the PC
/// (it listens for clipboard changes), Kotlin on the phone (the copy watcher
/// and the notification's Send). Both report copies as `copied` and take
/// `write`.
class ChannelClipboard implements DeviceClipboard {
  ChannelClipboard() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'copied') return;
      final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
      final text = args['text'];
      if (text is! String || text.isEmpty) return;
      final at = args['at'];
      _copies.add(
        Clip(
          text: text,
          sensitive: args['sensitive'] == true,
          manual: args['manual'] == true,
          at: at is int && at > 0
              ? DateTime.fromMillisecondsSinceEpoch(at)
              : null,
        ),
      );
    });
  }

  static const _channel = MethodChannel('app.gotit/clipboard');
  final _copies = StreamController<Clip>.broadcast();

  @override
  Stream<Clip> get copies => _copies.stream;

  @override
  Future<void> write(Clip clip) => _channel.invokeMethod<void>('write', {
    'text': clip.text,
    'sensitive': clip.sensitive,
  });
}
