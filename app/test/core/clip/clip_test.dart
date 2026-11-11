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

    test('a kind this version does not know is ignored', () {
      final frame = Frame(Frames.clip, const {'kind': 'image'});
      expect(Clip.fromFrame(frame), isNull);
    });

    test('over a mebibyte stays where it was copied', () {
      expect(Clip(text: 'x' * Clip.maxBytes).tooBig, isFalse);
      expect(Clip(text: 'x' * (Clip.maxBytes + 1)).tooBig, isTrue);
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
