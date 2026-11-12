import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

void main() {
  group('a clip', () {
    test('crosses as a frame and back, any script, sensitive kept', () {
      final at = DateTime(2026, 11, 11, 9, 30);
      final clip = Clip(
        text: 'Meeting at 9 - café, நன்றி',
        sensitive: true,
        at: at,
      );
      final back = Clip.fromFrame(clip.toFrame())!;
      expect(back.text, clip.text);
      expect(back.sensitive, isTrue);
      expect(back.at, at);
      expect(back.manual, isFalse);
    });

    test('an image crosses as a frame and back, bytes untouched', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final at = DateTime(2026, 11, 12, 9);
      final back = Clip.fromFrame(Clip(image: png, at: at).toFrame())!;
      expect(back.isImage, isTrue);
      expect(back.image, png);
      expect(back.text, isEmpty);
      expect(back.at, at);
    });

    test('an image frame with no picture is ignored', () {
      final frame = Frame(Frames.clip, const {'kind': 'image'}, Uint8List(0));
      expect(Clip.fromFrame(frame), isNull);
    });

    test('a kind this version does not know is ignored', () {
      final frame = Frame(Frames.clip, const {'kind': 'file'}, Uint8List(4));
      expect(Clip.fromFrame(frame), isNull);
    });

    test('over a mebibyte stays where it was copied', () {
      expect(Clip(text: 'x' * Clip.maxBytes).tooBig, isFalse);
      expect(Clip(text: 'x' * (Clip.maxBytes + 1)).tooBig, isTrue);
    });

    test('an image over 25 MiB stays where it was copied', () {
      expect(Clip(image: Uint8List(Clip.maxImageBytes)).tooBig, isFalse);
      expect(Clip(image: Uint8List(Clip.maxImageBytes + 1)).tooBig, isTrue);
    });

    test('the same picture has the same key, and never matches text', () {
      final one = Clip(image: Uint8List.fromList([1, 2, 3]));
      final again = Clip(image: Uint8List.fromList([1, 2, 3]));
      final other = Clip(image: Uint8List.fromList([3, 2, 1]));
      expect(one.key, again.key);
      expect(one.key, isNot(other.key));
      expect(Clip(text: one.key).key, one.key);
      expect(Clip(text: 'image').key, isNot(one.key));
    });
  });

  group('the guard', () {
    var now = DateTime(2026, 11, 11, 9);
    ClipGuard guard() => ClipGuard(clock: () => now);

    test('lets new copies through', () {
      final g = guard();
      expect(g.shouldSend('one'), isTrue);
      expect(g.shouldSend('two'), isTrue);
    });

    test('stops the other device\'s text bouncing back', () {
      final g = guard()..wrote('from the PC');
      expect(g.shouldSend('from the PC'), isFalse);
      expect(g.shouldSend('from the PC'), isFalse);
    });

    test('sends written text again once something else was copied', () {
      final g = guard()..wrote('from the PC');
      expect(g.shouldSend('something else'), isTrue);
      expect(g.shouldSend('from the PC'), isTrue);
    });

    test('one copy reported twice in a burst crosses once', () {
      final g = guard();
      expect(g.shouldSend('twice'), isTrue);
      now = now.add(const Duration(milliseconds: 500));
      expect(g.shouldSend('twice'), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(g.shouldSend('twice'), isTrue);
    });
  });
}
