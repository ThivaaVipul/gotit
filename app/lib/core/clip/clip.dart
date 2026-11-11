import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

/// Something copied: text for now (images come in M3).
class Clip {
  Clip({
    required this.text,
    this.sensitive = false,
    this.manual = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  /// Text above this many bytes stays where it was copied.
  static const maxBytes = 1024 * 1024;

  final String text;

  /// A password or code: kept out of clipboard history and previews.
  final bool sensitive;

  /// Sent on purpose (the notification's Send), not caught by a watcher.
  /// Only this device knows: the flag isn't part of the frame.
  final bool manual;

  /// When it was copied.
  final DateTime at;

  bool get tooBig => utf8.encode(text).length > maxBytes;

  Frame toFrame() => Frame(Frames.clip, {
    'kind': 'text',
    'sensitive': sensitive,
    'at': at.millisecondsSinceEpoch,
  }, Uint8List.fromList(utf8.encode(text)));

  /// The clip in [frame], or null when it isn't one this version understands.
  static Clip? fromFrame(Frame frame) {
    final body = frame.body;
    if (frame.text('kind') != 'text' || body == null) return null;
    try {
      final at = frame.number('at');
      return Clip(
        text: utf8.decode(body),
        sensitive: frame.fields['sensitive'] == true,
        at: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      );
    } on FormatException {
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
