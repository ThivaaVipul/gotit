import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/clip/bridge.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/recent/recent.dart';
import 'package:gotit/core/recent/recent_keeper.dart';

import '../../helpers.dart';

class FakeClipboard implements DeviceClipboard {
  final wiped = <Object>[];

  @override
  Stream<Clip> get copies => const Stream.empty();

  @override
  Future<Object?> write(Clip clip) async => null;

  @override
  Future<void> wipe(Object mark) async => wiped.add(mark);
}

void main() {
  late Directory folder;
  late RecentList list;
  late FakeClipboard clipboard;
  late List<Clip> copiedHere;
  late List<String> links;
  late RecentKeeper keeper;
  var mark = 0;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('gotit-keeper-');
    list = await RecentList.open(
      folder,
      sensitiveFor: const Duration(milliseconds: 40),
    );
    clipboard = FakeClipboard();
    copiedHere = [];
    links = [];
    keeper = RecentKeeper(
      list: list,
      clipboard: clipboard,
      copyHere: (clip) async {
        copiedHere.add(clip);
        return ++mark;
      },
      onLink: links.add,
    );
  });

  tearDown(() async {
    keeper.dispose();
    await list.flush();
    list.dispose();
    await folder.delete(recursive: true);
  });

  test('copies that cross are listed both ways', () async {
    await keeper.sent(Clip(text: 'out'));
    await keeper.arrived(Clip(text: 'in'), null);
    expect(list.value.map((i) => (i.text, i.way)), [
      ('in', RecentWay.received),
      ('out', RecentWay.sent),
    ]);
  });

  test('a link that arrives gets its notice; one sent does not', () async {
    await keeper.sent(Clip(text: 'https://example.com/out'));
    await keeper.arrived(Clip(text: 'https://example.com/in'), null);
    expect(links, ['https://example.com/in']);
  });

  test('a sensitive copy is wiped when its minute is up', () async {
    await keeper.arrived(Clip(text: 'secret', sensitive: true), 'mark-1');
    expect(clipboard.wiped, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(clipboard.wiped, ['mark-1']);
    expect(list.value, isEmpty);
  });

  test('a plain copy is never wiped', () async {
    await keeper.arrived(Clip(text: 'plain'), 'mark-1');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(clipboard.wiped, isEmpty);
  });

  test('copying again stays here, and moves the item up', () async {
    await keeper.arrived(Clip(text: 'one'), null);
    await keeper.arrived(Clip(text: 'two'), null);
    final ok = await keeper.copy(list.value.last);
    expect(ok, isTrue);
    expect(copiedHere.single.text, 'one');
    expect(list.value.first.text, 'one');
  });

  test('a sensitive item copied again is wiped by its new mark', () async {
    await keeper.arrived(Clip(text: 'secret', sensitive: true), 'first');
    await keeper.copy(list.value.single);
    expect(copiedHere.single.sensitive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(clipboard.wiped, [mark]);
  });

  test('an image goes back as itself; files do not go back', () async {
    await keeper.arrived(Clip(image: png(3, 4)), null);
    list.addFiles(const [RecentFile(name: 'a', size: 1)], RecentWay.sent);
    expect(await keeper.copy(list.value.first), isFalse);
    expect(await keeper.copy(list.value.last), isTrue);
    expect(copiedHere.single.image, png(3, 4));
  });
}
