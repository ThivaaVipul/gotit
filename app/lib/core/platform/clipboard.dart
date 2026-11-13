import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';

/// The clipboard through the platform side: the Windows runner on the PC
/// (it listens for clipboard changes), Kotlin on the phone (the copy watcher,
/// the notification's Send and new screenshots). Both report copies as
/// `copied` and take `write`, with `text`, or `image` as PNG bytes, and
/// `wipe`.
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
          screenshot: args['screenshot'] == true,
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

  /// The PC gives back the clipboard's sequence number after the write,
  /// which changes with any later copy. The phone can't watch its clipboard
  /// from the background, so text is checked by what it holds: its SHA-256.
  @override
  Future<Object?> write(Clip clip) async {
    final sequence = await _channel.invokeMethod<Object?>('write', {
      if (clip.isImage) 'image': clip.image else 'text': clip.text,
      'sensitive': clip.sensitive,
    });
    if (sequence is int) return sequence;
    if (clip.isImage) return null;
    return sha256.convert(utf8.encode(clip.text)).toString();
  }

  @override
  Future<void> wipe(Object mark) async {
    try {
      await _channel.invokeMethod<void>(
        'wipe',
        mark is int ? {'sequence': mark} : {'sha': '$mark'},
      );
    } on PlatformException {
      // Left on the clipboard; the next copy replaces it.
    } on MissingPluginException {
      // The same.
    }
  }
}
