import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/state/notice_keeper.dart';

class FakeNotice implements LinkNotice {
  final shown = <(String, String?)>[];
  int hidden = 0;

  @override
  Future<bool> show(String title, {String? text}) async {
    shown.add((title, text));
    return true;
  }

  @override
  Future<void> hide() async => hidden++;
}

const _pc = Peer(id: 'pc', name: 'Desk PC', certPem: 'x');

void main() {
  late StreamController<PhoneLinkState> states;
  late PhoneLinkState current;
  late FakeNotice notice;
  late NoticeKeeper keeper;

  setUp(() {
    states = StreamController<PhoneLinkState>.broadcast();
    current = const PhoneLinkState();
    notice = FakeNotice();
    keeper = NoticeKeeper(
      states: states.stream,
      current: () => current,
      notice: notice,
      sentFor: const Duration(milliseconds: 100),
    );
  });

  tearDown(() async {
    await keeper.stop();
    await states.close();
  });

  Future<void> change(PhoneLinkState next) async {
    current = next;
    states.add(next);
    await Future<void>.delayed(Duration.zero);
  }

  test('no notification until paired', () {
    keeper.start();
    expect(notice.shown, isEmpty);
  });

  test('follows the link, and says when a copy was sent', () async {
    keeper.start();
    await change(
      const PhoneLinkState(pc: _pc, connection: Connection.connecting),
    );
    expect(notice.shown.last, ('Looking for Desk PC', null));
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    expect(notice.shown.last, ('Connected to Desk PC', null));

    keeper.sent();
    expect(notice.shown.last, ('Connected to Desk PC', 'Sent to Desk PC'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(notice.shown.last, ('Connected to Desk PC', null));
  });

  test('goes away when the pairing is forgotten', () async {
    keeper.start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    await change(const PhoneLinkState());
    expect(notice.hidden, 1);
  });

  test('says when MIUI stopped the copy watcher', () async {
    final watcher = StreamController<WatcherState>.broadcast();
    final watched = NoticeKeeper(
      states: states.stream,
      current: () => current,
      notice: notice,
      watcher: watcher.stream,
    )..start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));

    watcher.add(WatcherState.stopped);
    await Future<void>.delayed(Duration.zero);
    expect(notice.shown.last, (
      'Connected to Desk PC',
      'Copy watching stopped',
    ));

    watcher.add(WatcherState.on);
    await Future<void>.delayed(Duration.zero);
    expect(notice.shown.last, ('Connected to Desk PC', null));

    // Android switches it off when MIUI force-stops the app.
    watcher.add(WatcherState.turnedOff);
    await Future<void>.delayed(Duration.zero);
    expect(notice.shown.last, ('Connected to Desk PC', 'Copy watching is off'));

    await watched.stop();
    await watcher.close();
  });

  test('does not repeat itself', () async {
    keeper.start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    expect(notice.shown, hasLength(1));
  });
}
