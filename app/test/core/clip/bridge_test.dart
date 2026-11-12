import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';

class FakeLink implements ClipLink {
  bool online = true;
  final sent = <String>[];
  final sentClips = <Clip>[];
  // Closed in tearDown.
  // ignore: close_sinks
  final incoming = StreamController<Clip>.broadcast();

  @override
  bool sendClip(Clip clip) {
    if (!online) return false;
    sent.add(clip.text);
    sentClips.add(clip);
    return true;
  }

  @override
  Stream<Clip> get clips => incoming.stream;
}

class FakeClipboard implements DeviceClipboard {
  // Closed in tearDown.
  // ignore: close_sinks
  final local = StreamController<Clip>.broadcast();
  final written = <Clip>[];

  @override
  Stream<Clip> get copies => local.stream;

  @override
  Future<void> write(Clip clip) async => written.add(clip);
}

void main() {
  late FakeLink link;
  late FakeClipboard clipboard;
  late List<String> sentSigns;
  late List<String> arrivals;
  late bool sharingOn;

  tearDown(() async {
    await link.incoming.close();
    await clipboard.local.close();
  });

  setUp(() {
    link = FakeLink();
    clipboard = FakeClipboard();
    sentSigns = [];
    arrivals = [];
    sharingOn = true;
    ClipBridge(
      link: link,
      clipboard: clipboard,
      sharing: () => sharingOn,
      onSent: (clip) => sentSigns.add(clip.text),
      onArrived: (clip) => arrivals.add(clip.text),
    ).start();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a copy made here crosses, with the sent sign', () async {
    clipboard.local.add(Clip(text: 'hello'));
    await settle();
    expect(link.sent, ['hello']);
    expect(sentSigns, ['hello']);
  });

  test('a copy made while the other device is away is dropped', () async {
    link.online = false;
    clipboard.local.add(Clip(text: 'lost'));
    await settle();
    expect(link.sent, isEmpty);
    expect(sentSigns, isEmpty);
  });

  test('what arrives goes on the clipboard and is not sent back', () async {
    link.incoming.add(Clip(text: 'from the PC', sensitive: true));
    await settle();
    expect(clipboard.written.single.text, 'from the PC');
    expect(clipboard.written.single.sensitive, isTrue);
    expect(arrivals, ['from the PC']);

    // The phone's watcher reports the write as a copy.
    clipboard.local.add(Clip(text: 'from the PC'));
    await settle();
    expect(link.sent, isEmpty);
  });

  test('Send on purpose always sends', () async {
    link.incoming.add(Clip(text: 'from the PC'));
    await settle();
    clipboard.local.add(Clip(text: 'from the PC', manual: true));
    await settle();
    expect(link.sent, ['from the PC']);
  });

  test('nothing crosses either way while sharing is off', () async {
    sharingOn = false;
    clipboard.local.add(Clip(text: 'kept here'));
    clipboard.local.add(Clip(text: 'sent on purpose', manual: true));
    link.incoming.add(Clip(text: 'from the PC'));
    await settle();
    expect(link.sent, isEmpty);
    expect(clipboard.written, isEmpty);
    expect(sentSigns, isEmpty);
  });

  test(
    'an image crosses, and the same one coming back is not echoed',
    () async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 9, 9]);
      clipboard.local.add(Clip(image: png));
      await settle();
      expect(link.sentClips.single.image, png);

      link.incoming.add(Clip(image: Uint8List.fromList([7, 7, 7])));
      await settle();
      expect(clipboard.written.single.isImage, isTrue);
      // The phone's watcher reports the written image as a copy.
      clipboard.local.add(Clip(image: Uint8List.fromList([7, 7, 7])));
      await settle();
      expect(link.sentClips, hasLength(1));
    },
  );

  test('an image over the limit stays put either way', () async {
    clipboard.local.add(Clip(image: Uint8List(Clip.maxImageBytes + 1)));
    link.incoming.add(Clip(image: Uint8List(Clip.maxImageBytes + 1)));
    await settle();
    expect(link.sentClips, isEmpty);
    expect(clipboard.written, isEmpty);
  });

  test('sending now goes past the guard, but not while off or away', () async {
    link.incoming.add(Clip(text: 'shared'));
    await settle();
    final bridge = ClipBridge(
      link: link,
      clipboard: clipboard,
      sharing: () => sharingOn,
    );
    expect(bridge.sendNow(Clip(text: 'shared', manual: true)), isTrue);
    sharingOn = false;
    expect(bridge.sendNow(Clip(text: 'shared', manual: true)), isFalse);
    sharingOn = true;
    link.online = false;
    expect(bridge.sendNow(Clip(text: 'shared', manual: true)), isFalse);
    expect(link.sent, ['shared']);
  });

  test('empty or oversized copies stay put', () async {
    clipboard.local
      ..add(Clip(text: ''))
      ..add(Clip(text: 'x' * (Clip.maxBytes + 1)));
    await settle();
    expect(link.sent, isEmpty);
  });
}
