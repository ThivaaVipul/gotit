import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/clip/clip.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/recent/recent.dart';
import 'package:gotit/core/recent/recent_actions.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/features/home/widgets/recent_card.dart';
import 'package:gotit/features/home/widgets/recent_row.dart';

class FakeActions implements RecentActions {
  final done = <String>[];

  @override
  Future<bool> copy(RecentItem item) async {
    done.add('copy ${item.text}');
    return true;
  }

  @override
  void openLink(String url) => done.add('openLink $url');

  @override
  void open(RecentItem item) => done.add('open');

  @override
  void reveal(RecentItem item) => done.add('reveal');

  @override
  void openFolder(RecentItem item) => done.add('openFolder');

  @override
  void share(RecentItem item) => done.add('share');
}

void main() {
  late Directory dir;
  late SettingsStore settings;
  late RecentList list;
  late FakeActions actions;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('gotit_recent_card_');
    settings = await SettingsStore.open(File('${dir.path}/settings.json'));
    await settings.save(
      settings.value.copyWith(
        peer: () => const Peer(id: 'pc', name: 'Desk', certPem: 'x'),
      ),
    );
    list = RecentList.unsaved();
    actions = FakeActions();
  });

  tearDown(() {
    list.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, {bool isPc = false}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: gotitTheme(Brightness.light),
          home: Scaffold(
            body: ListView(
              children: [
                RecentCard(
                  list: list,
                  actions: actions,
                  isPc: isPc,
                  settings: settings,
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> add(WidgetTester tester, Clip clip, RecentWay way) async {
    await list.addClip(clip, way);
  }

  testWidgets('says so while nothing has crossed', (tester) async {
    await pump(tester);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('lists text, links and files, newest first', (tester) async {
    await add(tester, Clip(text: 'first line\nsecond'), RecentWay.sent);
    await add(
      tester,
      Clip(text: 'https://example.com/docs'),
      RecentWay.received,
    );
    list.addFiles(const [
      RecentFile(name: 'IMG_1.jpg', size: 2000000, location: '/d/IMG_1.jpg'),
      RecentFile(name: 'IMG_2.jpg', size: 400000, location: '/d/IMG_2.jpg'),
    ], RecentWay.received);
    await pump(tester);
    expect(find.text('first line'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open'), findsOneWidget);
    expect(find.textContaining('IMG_1.jpg'), findsOneWidget);
    expect(find.text('2.4 MB'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('a tap copies it here and says Copied', (tester) async {
    await add(tester, Clip(text: 'hello'), RecentWay.received);
    await pump(tester);
    await tester.tap(find.text('hello'));
    await tester.pump();
    expect(actions.done, ['copy hello']);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('Open on a link opens it', (tester) async {
    await add(tester, Clip(text: 'https://example.com'), RecentWay.received);
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Open'));
    expect(actions.done, ['openLink https://example.com']);
  });

  testWidgets('a sensitive copy shows as dots', (tester) async {
    await add(tester, Clip(text: 'hunter2', sensitive: true), RecentWay.sent);
    await pump(tester);
    expect(find.text('hunter2'), findsNothing);
    expect(find.text(hiddenText), findsOneWidget);
    // Its minute runs out, and it leaves.
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(hiddenText), findsNothing);
  });

  testWidgets('Clear empties it, and Undo brings it back', (tester) async {
    await add(tester, Clip(text: 'one'), RecentWay.sent);
    await add(tester, Clip(text: 'two'), RecentWay.sent);
    await pump(tester);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.text('Cleared'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('a long press on the phone offers Remove', (tester) async {
    await add(tester, Clip(text: 'keep'), RecentWay.sent);
    await add(tester, Clip(text: 'drop'), RecentWay.sent);
    await pump(tester);
    await tester.longPress(find.text('drop'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('drop'), findsNothing);
    expect(find.text('keep'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
    // Past Undo: gone for good.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.text('Removed'), findsNothing);
  });

  testWidgets('files that arrived open on a tap', (tester) async {
    list.addFiles(const [
      RecentFile(name: 'a.pdf', size: 10, location: 'content://a'),
    ], RecentWay.received);
    list.addFiles(const [
      RecentFile(name: 'b.pdf', size: 10, location: 'content://b'),
      RecentFile(name: 'c.pdf', size: 10, location: 'content://c'),
    ], RecentWay.received);
    await pump(tester);
    await tester.tap(find.text('a.pdf'));
    await tester.tap(find.textContaining('b.pdf'));
    expect(actions.done, ['open', 'openFolder']);
  });

  group('words', () {
    final now = DateTime(2026, 11, 13, 12);

    test('when it was', () {
      expect(recentAgo(now.subtract(const Duration(seconds: 10)), now), 'now');
      expect(recentAgo(now.subtract(const Duration(minutes: 5)), now), '5 min');
      expect(recentAgo(now.subtract(const Duration(hours: 3)), now), '3 h');
      expect(recentAgo(DateTime(2026, 11, 12, 9), now), 'Yesterday');
      expect(recentAgo(DateTime(2026, 11, 9, 9), now), 'Mon');
      expect(recentAgo(DateTime(2026, 10, 2, 9), now), '2 Oct');
    });

    test('how big', () {
      expect(fileSize(-1), '');
      expect(fileSize(512), '512 B');
      expect(fileSize(18000), '18 KB');
      expect(fileSize(2400000), '2.4 MB');
      expect(fileSize(1200000000), '1.2 GB');
    });

    test('what kind of file', () {
      expect(fileBadge('report.pdf'), 'PDF');
      expect(fileBadge('notes'), isNull);
      expect(fileBadge('archive.longext'), isNull);
    });
  });
}
