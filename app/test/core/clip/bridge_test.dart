import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';

class FakeLink implements ClipLink {
  bool online = true;
  final sent = <String>[];
  // Closed in tearDown.
  // ignore: close_sinks
  final incoming = StreamController<Clip>.broadcast();

  @override
  bool sendClip(Clip clip) {
    if (!online) return false;
    sent.add(clip.text);
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

  tearDown(() async {
    await link.incoming.close();
    await clipboard.local.close();
  });

  setUp(() {
    link = FakeLink();
    clipboard = FakeClipboard();
    sentSigns = [];
    arrivals = [];
    ClipBridge(
      link: link,
      clipboard: clipboard,
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

  test('empty or oversized copies stay put', () async {
    clipboard.local
      ..add(Clip(text: ''))
      ..add(Clip(text: 'x' * (Clip.maxBytes + 1)));
    await settle();
    expect(link.sent, isEmpty);
  });
}
