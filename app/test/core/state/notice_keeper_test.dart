import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/notice_keeper.dart';
import 'package:gotit/core/transfer/transfers.dart';

class FakeNotice implements LinkNotice {
  final shown = <(String, String?)>[];
  final sharing = <bool>[];
  final progress = <(int?, String?)>[];
  int hidden = 0;

  @override
  Future<bool> show(
    String title, {
    String? text,
    bool sharing = true,
    int? percent,
    String? cancel,
  }) async {
    shown.add((title, text));
    this.sharing.add(sharing);
    progress.add((percent, cancel));
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

  test('says when sharing is off, with Turn on', () async {
    final sharing = ValueNotifier(SharingState.initial);
    final kept = NoticeKeeper(
      states: states.stream,
      current: () => current,
      notice: notice,
      sharing: sharing,
    )..start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    expect(notice.sharing.last, isTrue);

    sharing.value = SharingState(on: false, changedAt: DateTime(2026));
    expect(notice.shown.last, ('Sharing off', 'Connected to Desk PC'));
    expect(notice.sharing.last, isFalse);

    sharing.value = SharingState(on: true, changedAt: DateTime(2027));
    expect(notice.shown.last, ('Connected to Desk PC', null));
    expect(notice.sharing.last, isTrue);

    await kept.stop();
    sharing.dispose();
  });

  test('a file being sent shows its progress and Cancel, then Sent', () async {
    final files = ValueNotifier<List<Transfer>>(const []);
    final kept = NoticeKeeper(
      states: states.stream,
      current: () => current,
      notice: notice,
      transfers: files,
    )..start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));

    const sending = Transfer(
      id: 't1',
      name: 'video.mp4',
      size: 1000,
      direction: TransferDirection.sending,
      bytes: 250,
    );
    files.value = [sending];
    expect(notice.shown.last, ('Sending to Desk PC', 'video.mp4'));
    expect(notice.progress.last, (25, 't1'));

    files.value = [sending.copyWith(status: TransferStatus.done, bytes: 1000)];
    expect(notice.shown.last, ('Connected to Desk PC', 'Sent to Desk PC'));
    expect(notice.progress.last, (null, null));

    await kept.stop();
    files.dispose();
  });

  test('a file arriving shows its progress and Cancel', () async {
    final files = ValueNotifier<List<Transfer>>(const []);
    final kept = NoticeKeeper(
      states: states.stream,
      current: () => current,
      notice: notice,
      transfers: files,
    )..start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));

    const receiving = Transfer(
      id: 't2',
      name: 'slides.pdf',
      size: 400,
      direction: TransferDirection.receiving,
      bytes: 100,
    );
    files.value = [receiving];
    expect(notice.shown.last, ('Receiving from Desk PC', 'slides.pdf'));
    expect(notice.progress.last, (25, 't2'));

    files.value = [receiving.copyWith(status: TransferStatus.done, bytes: 400)];
    expect(notice.shown.last, ('Connected to Desk PC', null));
    expect(notice.progress.last, (null, null));

    await kept.stop();
    files.dispose();
  });

  test('does not repeat itself', () async {
    keeper.start();
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    await change(const PhoneLinkState(pc: _pc, connection: Connection.online));
    expect(notice.shown, hasLength(1));
  });
}
