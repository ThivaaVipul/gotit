import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/recent/recent.dart';

import '../../helpers.dart';

void main() {
  late Directory folder;
  final opened = <RecentList>[];

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('gotit-recent-');
  });

  tearDown(() async {
    for (final list in opened) {
      await list.flush();
      list.dispose();
    }
    opened.clear();
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  Future<RecentList> open({
    int max = 20,
    Duration sensitiveFor = const Duration(minutes: 1),
    int maxImageBytes = 100 * 1024 * 1024,
    Duration undoFor = const Duration(seconds: 8),
  }) async {
    final list = await RecentList.open(
      folder,
      max: max,
      sensitiveFor: sensitiveFor,
      maxImageBytes: maxImageBytes,
      undoFor: undoFor,
    );
    opened.add(list);
    return list;
  }

  /// As Gotit quitting: everything on disk, then gone.
  Future<void> close(RecentList list) async {
    await list.flush();
    list.dispose();
    opened.remove(list);
  }

  Directory images() =>
      Directory('${folder.path}${Platform.pathSeparator}recent');

  group('links', () {
    test('one web address is a link', () {
      expect(isWebLink('https://example.com/a?b=1'), isTrue);
      expect(isWebLink('  http://example.com  '), isTrue);
    });

    test('anything more, or another scheme, is not', () {
      expect(isWebLink('see https://example.com'), isFalse);
      expect(isWebLink('example.com'), isFalse);
      expect(isWebLink('ftp://example.com'), isFalse);
      expect(isWebLink('javascript:alert(1)'), isFalse);
      expect(isWebLink('https://'), isFalse);
      expect(isWebLink(''), isFalse);
    });

    test('shown without the scheme', () {
      expect(shownLink('https://example.com/a'), 'example.com/a');
      expect(shownLink('HTTP://example.com'), 'example.com');
    });
  });

  test('a PNG says its size in its header', () {
    expect(pngSize(png(1080, 2400)), (1080, 2400));
    expect(pngSize(Uint8List.fromList([1, 2, 3])), (0, 0));
  });

  test('text and links arrive newest first', () async {
    final list = await open();
    await list.addClip(Clip(text: 'hello'), RecentWay.sent);
    await list.addClip(Clip(text: 'https://example.com'), RecentWay.received);
    expect(list.value.map((i) => i.kind), [RecentKind.link, RecentKind.text]);
    expect(list.value.first.way, RecentWay.received);
    expect(list.value.last.text, 'hello');
  });

  test('a sensitive link is plain text: no Open, no notice', () async {
    final list = await open();
    final item = await list.addClip(
      Clip(text: 'https://example.com/reset?token=x', sensitive: true),
      RecentWay.received,
    );
    expect(item!.kind, RecentKind.text);
    expect(item.sensitive, isTrue);
  });

  test('the same text again moves to the top, not twice', () async {
    final list = await open();
    await list.addClip(Clip(text: 'one'), RecentWay.sent);
    await list.addClip(Clip(text: 'two'), RecentWay.sent);
    await list.addClip(Clip(text: 'one'), RecentWay.received);
    expect(list.value.map((i) => i.text), ['one', 'two']);
  });

  test('only the newest are kept', () async {
    final list = await open(max: 3);
    for (final text in ['a', 'b', 'c', 'd']) {
      await list.addClip(Clip(text: text), RecentWay.sent);
    }
    expect(list.value.map((i) => i.text), ['d', 'c', 'b']);
  });

  test('an image is kept as a PNG file, with its size', () async {
    final list = await open();
    final item = await list.addClip(
      Clip(image: png(1080, 2400), screenshot: true),
      RecentWay.received,
    );
    expect(item!.kind, RecentKind.image);
    expect(item.screenshot, isTrue);
    expect((item.width, item.height), (1080, 2400));
    expect(File(item.image!).readAsBytesSync(), png(1080, 2400));
  });

  test('the same image again moves to the top', () async {
    final list = await open();
    await list.addClip(Clip(image: png(10, 10)), RecentWay.sent);
    await list.addClip(Clip(text: 'between'), RecentWay.sent);
    await list.addClip(Clip(image: png(10, 10)), RecentWay.received);
    expect(list.value.map((i) => i.kind), [RecentKind.image, RecentKind.text]);
    expect(images().listSync(), hasLength(1));
  });

  test('a sensitive image crosses but is not listed', () async {
    final list = await open();
    final item = await list.addClip(
      Clip(image: png(10, 10), sensitive: true),
      RecentWay.received,
    );
    expect(item, isNull);
    expect(list.value, isEmpty);
  });

  test('images past the cap leave, oldest first', () async {
    final list = await open(maxImageBytes: 250);
    final first = await list.addClip(
      Clip(image: png(1, 1, extra: 80, seed: 1)),
      RecentWay.sent,
    );
    await list.addClip(Clip(text: 'text stays'), RecentWay.sent);
    await list.addClip(
      Clip(image: png(2, 2, extra: 80, seed: 2)),
      RecentWay.sent,
    );
    await list.addClip(
      Clip(image: png(3, 3, extra: 80, seed: 3)),
      RecentWay.sent,
    );
    expect(list.value.map((i) => i.width), [3, 2, 0]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(File(first!.image!).existsSync(), isFalse);
  });

  test('files that went together are one item', () async {
    final list = await open();
    final item = list.addFiles(
      const [
        RecentFile(name: 'a.jpg', size: 100, location: '/d/a.jpg'),
        RecentFile(name: 'b.jpg', size: -1),
      ],
      RecentWay.received,
      batch: 'b1',
    );
    expect(item!.kind, RecentKind.files);
    expect(item.copyable, isFalse);
    expect(item.totalSize, 100);
    expect(list.value.single.batch, 'b1');
  });

  test('kept across restarts, sensitive items never written', () async {
    final list = await open();
    await list.addClip(Clip(text: 'hello'), RecentWay.sent);
    await list.addClip(Clip(text: 'secret', sensitive: true), RecentWay.sent);
    await list.addClip(Clip(image: png(4, 5)), RecentWay.received);
    list.addFiles(const [
      RecentFile(name: 'a.txt', size: 3, location: '/d/a.txt'),
    ], RecentWay.received);
    await list.flush();
    final saved = File('${folder.path}${Platform.pathSeparator}recent.json');
    expect(saved.readAsStringSync(), isNot(contains('secret')));
    await close(list);

    final again = await open();
    expect(again.value.map((i) => i.kind), [
      RecentKind.files,
      RecentKind.image,
      RecentKind.text,
    ]);
    expect((again.value[1].width, again.value[1].height), (4, 5));
    expect(again.value[0].files.single.location, '/d/a.txt');
    expect(again.value[2].text, 'hello');
    await close(again);
  });

  test('an item whose image is gone is dropped at start', () async {
    final list = await open();
    final item = await list.addClip(Clip(image: png(4, 5)), RecentWay.sent);
    await list.flush();
    await close(list);
    File(item!.image!).deleteSync();
    final again = await open();
    expect(again.value, isEmpty);
    await close(again);
  });

  test('images no item uses are deleted at start', () async {
    images().createSync(recursive: true);
    final stray = File('${images().path}${Platform.pathSeparator}old.png')
      ..writeAsBytesSync([1]);
    final list = await open();
    expect(stray.existsSync(), isFalse);
    await close(list);
  });

  test('a damaged list starts empty', () async {
    File(
      '${folder.path}${Platform.pathSeparator}recent.json',
    ).writeAsStringSync('{not json');
    final list = await open();
    expect(list.value, isEmpty);
    await close(list);
  });

  test('items from a newer or broken list are skipped', () async {
    File(
      '${folder.path}${Platform.pathSeparator}recent.json',
    ).writeAsStringSync(
      jsonEncode({
        'items': [
          {'id': 'a', 'kind': 'hologram', 'way': 'sent', 'at': 1},
          {'id': 'b', 'kind': 'text', 'way': 'sent', 'at': 2},
          {'id': 'c', 'kind': 'text', 'way': 'sent', 'at': 3, 'text': 'ok'},
        ],
      }),
    );
    final list = await open();
    expect(list.value.single.text, 'ok');
    await close(list);
  });

  test('a sensitive item leaves after its minute', () async {
    final list = await open(sensitiveFor: const Duration(milliseconds: 30));
    await list.addClip(Clip(text: 'secret', sensitive: true), RecentWay.sent);
    await list.addClip(Clip(text: 'plain'), RecentWay.sent);
    expect(list.value, hasLength(2));
    expect(list.deadlineOf(list.value.last.id), isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(list.value.map((i) => i.text), ['plain']);
    await close(list);
  });

  test('copying again moves an item to the top, as of now', () async {
    final list = await open();
    final first = await list.addClip(Clip(text: 'one'), RecentWay.sent);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await list.addClip(Clip(text: 'two'), RecentWay.sent);
    final moved = list.copiedAgain(first!.id);
    expect(list.value.map((i) => i.text), ['one', 'two']);
    expect(moved!.at.isAfter(first.at), isTrue);
    await close(list);
  });

  test('a removed item comes back with Undo, image and all', () async {
    final list = await open(undoFor: const Duration(milliseconds: 40));
    final image = await list.addClip(Clip(image: png(2, 2)), RecentWay.sent);
    await list.addClip(Clip(text: 'newer'), RecentWay.sent);
    final gone = list.remove(image!.id);
    expect(list.value.map((i) => i.text), ['newer']);
    list.restore([gone!]);
    expect(list.value.map((i) => i.kind), [RecentKind.text, RecentKind.image]);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(File(image.image!).existsSync(), isTrue);
    await close(list);
  });

  test('a removed image is deleted once Undo has passed', () async {
    final list = await open(undoFor: const Duration(milliseconds: 20));
    final image = await list.addClip(Clip(image: png(2, 2)), RecentWay.sent);
    list.remove(image!.id);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(File(image.image!).existsSync(), isFalse);
    await close(list);
  });

  test('Clear empties the list, and Undo brings it all back', () async {
    final list = await open();
    for (final text in ['a', 'b', 'c']) {
      await list.addClip(Clip(text: text), RecentWay.sent);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final gone = list.clear();
    expect(list.value, isEmpty);
    list.restore(gone);
    expect(list.value.map((i) => i.text), ['c', 'b', 'a']);
    await close(list);
  });

  test('a sensitive item past its minute stays gone after Undo', () async {
    final list = await open(sensitiveFor: const Duration(milliseconds: 20));
    final item = await list.addClip(
      Clip(text: 'secret', sensitive: true),
      RecentWay.received,
    );
    final gone = list.remove(item!.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    list.restore([gone!]);
    expect(list.value, isEmpty);
    await close(list);
  });
}
