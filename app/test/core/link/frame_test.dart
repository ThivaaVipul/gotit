import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/frame.dart';

Future<List<Frame>> decode(List<List<int>> chunks) =>
    const FrameDecoder().bind(Stream.fromIterable(chunks)).toList();

void main() {
  test('frames survive any split of the bytes', () async {
    final frames = [
      const Frame('hello', {'id': 'abc', 'v': 1}),
      Frame('clip', const {'kind': 'text'}, Uint8List.fromList([1, 2, 3, 4])),
      const Frame('ping'),
    ];
    final bytes = frames.expand(encodeFrame).toList();
    final random = Random(7);
    for (var round = 0; round < 50; round++) {
      final chunks = <List<int>>[];
      var at = 0;
      while (at < bytes.length) {
        final size = 1 + random.nextInt(9);
        chunks.add(bytes.sublist(at, min(at + size, bytes.length)));
        at += size;
      }
      final got = await decode(chunks);
      expect(got.map((f) => f.type), ['hello', 'clip', 'ping']);
      expect(got[0].text('id'), 'abc');
      expect(got[0].number('v'), 1);
      expect(got[1].body, [1, 2, 3, 4]);
      expect(got[2].body, isNull);
    }
  });

  test('a header without a type ends the stream', () async {
    final header = utf8.encode('{"id": "x"}');
    final bytes = ByteData(8 + header.length)
      ..setUint32(0, header.length)
      ..setUint32(4 + header.length, 0);
    final raw = bytes.buffer.asUint8List()
      ..setRange(4, 4 + header.length, header);
    expect(decode([raw]), throwsFormatException);
  });

  test('an oversized frame ends the stream before it is read', () async {
    final raw = ByteData(4)..setUint32(0, FrameLimits.header + 1);
    expect(decode([raw.buffer.asUint8List()]), throwsFormatException);
  });

  test('a link that ends mid-frame is an error', () async {
    final bytes = encodeFrame(const Frame('hello'));
    expect(decode([bytes.sublist(0, bytes.length - 1)]), throwsFormatException);
  });
}
