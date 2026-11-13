import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

/// Something copied: text, or an image as PNG.
class Clip {
  Clip({
    this.text = '',
    this.image,
    this.sensitive = false,
    this.manual = false,
    this.screenshot = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// Text above this many bytes stays where it was copied.
  static const maxBytes = 1024 * 1024;

  /// An image above this many bytes stays where it was copied.
  static const maxImageBytes = 25 * 1024 * 1024;

  /// The text, or empty for an image.
  final String text;

  /// The image as PNG, or null for text.
  final Uint8List? image;

  bool get isImage => image != null;

  bool get isEmpty => isImage ? image!.isEmpty : text.isEmpty;

  /// A password or code: kept out of clipboard history and previews.
  final bool sensitive;

  /// Sent on purpose (the notification's Send), not caught by a watcher.
  /// Only this device knows: the flag isn't part of the frame.
  final bool manual;

  /// A new phone screenshot rather than a copy (an image only).
  final bool screenshot;

  /// When it was copied.
  final DateTime at;

  bool get tooBig => isImage
      ? image!.length > maxImageBytes
      : utf8.encode(text).length > maxBytes;

  /// What the echo guard compares: the text, or a digest of the image.
  String get key => isImage ? 'image:${sha256.convert(image!)}' : text;

  Frame toFrame() => Frame(Frames.clip, {
    'kind': isImage ? 'image' : 'text',
    'sensitive': sensitive,
    'at': at.millisecondsSinceEpoch,
    // Older peers ignore it.
    if (screenshot) 'screenshot': true,
  }, image ?? Uint8List.fromList(utf8.encode(text)));

  /// The clip in [frame], or null when it isn't one this version understands.
  static Clip? fromFrame(Frame frame) {
    final body = frame.body;
    if (body == null) return null;
    final at = frame.number('at');
    final when = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    final sensitive = frame.fields['sensitive'] == true;
    switch (frame.text('kind')) {
      case 'text':
        try {
          return Clip(text: utf8.decode(body), sensitive: sensitive, at: when);
        } on FormatException {
          return null;
        }
      case 'image':
        if (body.isEmpty) return null;
        return Clip(
          image: body,
          sensitive: sensitive,
          screenshot: frame.fields['screenshot'] == true,
          at: when,
        );
      default:
        return null;
    }
  }
}

/// Stops copies from bouncing back and forth, and doubles from crossing twice.
///
/// It keeps digests, never the text itself.
class ClipGuard {
  ClipGuard({
    this.burst = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The same text copied again within this is one copy, not two.
  final Duration burst;
  final DateTime Function() _clock;

  String? _written;
  String? _sent;
  DateTime? _sentAt;

  static String _digest(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// The other device's text was just written here: when this device then
  /// reports it as a copy, it is an echo, not something to send back.
  void wrote(String text) => _written = _digest(text);

  /// Whether a copy made here should cross.
  bool shouldSend(String text) {
    final digest = _digest(text);
    // Our own write showing up as a copy.
    if (digest == _written) return false;
    final now = _clock();
    if (digest == _sent &&
        _sentAt != null &&
        now.difference(_sentAt!) < burst) {
      return false;
    }
    // Something else was copied here, so copying the written text again
    // later is deliberate.
    _written = null;
    _sent = digest;
    _sentAt = now;
    return true;
  }
}
