import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// One message on the link: a type, a few JSON fields and an optional body.
///
/// On the wire: a 4-byte header length, the header as UTF-8 JSON (its `t` is
/// the type), a 4-byte body length and the body. Lengths are big-endian.
class Frame {
  const Frame(this.type, [this.fields = const {}, this.body]);

  final String type;
  final Map<String, Object?> fields;
  final Uint8List? body;

  /// A string field, or null when it is missing or not a string.
  String? text(String key) {
    final value = fields[key];
    return value is String ? value : null;
  }

  /// A whole-number field, or null when it is missing or not a number.
  int? number(String key) {
    final value = fields[key];
    return value is int ? value : null;
  }

  @override
  String toString() =>
      'Frame($type, ${fields.keys.join(',')}, '
      '${body?.length ?? 0} bytes)';
}

/// Header and body limits. A frame over either one ends the connection.
abstract final class FrameLimits {
  static const header = 64 * 1024;
  static const body = 2 * 1024 * 1024;
}

Uint8List encodeFrame(Frame frame) {
  final header = utf8.encode(jsonEncode({...frame.fields, 't': frame.type}));
  final body = frame.body ?? Uint8List(0);
  if (header.length > FrameLimits.header || body.length > FrameLimits.body) {
    throw ArgumentError('Frame ${frame.type} is too big to send');
  }
  final out = Uint8List(8 + header.length + body.length);
  final view = ByteData.sublistView(out);
  view.setUint32(0, header.length);
  out.setRange(4, 4 + header.length, header);
  view.setUint32(4 + header.length, body.length);
  out.setRange(8 + header.length, out.length, body);
  return out;
}

/// Turns a byte stream into frames, however the bytes are split up on the way.
/// A malformed or oversized frame ends the stream with a [FormatException].
class FrameDecoder extends StreamTransformerBase<List<int>, Frame> {
  const FrameDecoder();

  @override
  Stream<Frame> bind(Stream<List<int>> stream) async* {
    final reader = FrameReader();
    await for (final chunk in stream) {
      for (final frame in reader.add(chunk)) {
        yield frame;
      }
    }
    if (reader.hasPartial) {
      throw const FormatException('The link ended in the middle of a frame');
    }
  }
}

/// The incremental parser behind [FrameDecoder].
class FrameReader {
  final _buffer = BytesBuilder();
  Uint8List _pending = Uint8List(0);

  bool get hasPartial => _pending.isNotEmpty;

  /// Adds [chunk] and returns every frame it completes.
  List<Frame> add(List<int> chunk) {
    _buffer
      ..add(_pending)
      ..add(chunk);
    var bytes = _buffer.takeBytes();
    final frames = <Frame>[];
    while (true) {
      final frame = _parse(bytes);
      if (frame == null) break;
      frames.add(frame.$1);
      bytes = Uint8List.sublistView(bytes, frame.$2);
    }
    _pending = Uint8List.fromList(bytes);
    return frames;
  }

  /// One frame from the start of [bytes] and its length, or null while it is
  /// still incomplete.
  static (Frame, int)? _parse(Uint8List bytes) {
    if (bytes.length < 4) return null;
    final view = ByteData.sublistView(bytes);
    final headerLength = view.getUint32(0);
    if (headerLength > FrameLimits.header) {
      throw const FormatException('A frame header is too big');
    }
    if (bytes.length < 8 + headerLength) return null;
    final bodyLength = view.getUint32(4 + headerLength);
    if (bodyLength > FrameLimits.body) {
      throw const FormatException('A frame body is too big');
    }
    final end = 8 + headerLength + bodyLength;
    if (bytes.length < end) return null;

    final Object? json;
    try {
      json = jsonDecode(
        utf8.decode(Uint8List.sublistView(bytes, 4, 4 + headerLength)),
      );
    } on FormatException {
      throw const FormatException('A frame header is not JSON');
    }
    if (json is! Map<String, Object?> || json['t'] is! String) {
      throw const FormatException('A frame header has no type');
    }
    final type = json.remove('t')! as String;
    final body = bodyLength == 0
        ? null
        : Uint8List.fromList(
            Uint8List.sublistView(bytes, 8 + headerLength, end),
          );
    return (Frame(type, json, body), end);
  }
}
