import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';

/// The clipboard through the platform side: the Windows runner on the PC
/// (it listens for clipboard changes), Kotlin on the phone (the copy watcher,
/// the notification's Send and new screenshots). Both report copies as
/// `copied` and take `write`, with `text`, or `image` as PNG bytes.
class ChannelClipboard implements DeviceClipboard {
  ChannelClipboard() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'copied') return;
      final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
      final text = args['text'];
      final image = args['image'];
      if (image is! Uint8List && (text is! String || text.isEmpty)) return;
      final at = args['at'];
      _copies.add(
        Clip(
          text: text is String ? text : '',
          image: image is Uint8List ? image : null,
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

  /// The PC only: [paths] on the clipboard as files, ready to paste, and
  /// the image at [picture] as a picture too.
  Future<void> writeFiles(List<String> paths, {String? picture}) => _channel
      .invokeMethod<void>('writeFiles', {'paths': paths, 'picture': ?picture});

  @override
  Future<void> write(Clip clip) => _channel.invokeMethod<void>('write', {
    if (clip.isImage) 'image': clip.image else 'text': clip.text,
    'sensitive': clip.sensitive,
  });
}
