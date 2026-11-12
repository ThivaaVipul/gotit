import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/transfer/folder_store.dart';
import 'package:gotit/core/transfer/pc_sender.dart';
import 'package:gotit/core/transfer/transfers.dart';
import 'package:gotit/core/transfer/zipped_folder.dart';

class FakeLink implements FileLink {
  bool up = true;
  // Closed in tearDown.
  // ignore: close_sinks
  final changes = StreamController<bool>.broadcast();

  @override
  bool get linked => up;

  @override
  Stream<bool> get linkedChanges => changes.stream;

  @override
  set fileFrameHandler(Future<void> Function(Frame frame)? handler) {}

  @override
  Future<bool> sendFileFrame(Frame frame) async => up;
}

/// Records what it was asked to send instead of sending it.
class RecordingTransfers extends Transfers {
  RecordingTransfers(FileLink link)
    : super(
        link: link,
        store: GatedStore(null, open: () => false),
      );

  final sent = <List<OutgoingFile>>[];

  @override
  Future<SendResult> send(List<OutgoingFile> files) async {
    sent.add(files);
    return SendResult.sent;
  }
}

void main() {
  late Directory dir;
  late FakeLink link;
  late RecordingTransfers transfers;
  late String? phone;
  late bool sharing;
  late DateTime clock;
  late PcSender sender;

  String at(String name) => '${dir.path}${Platform.pathSeparator}$name';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gotit_send_');
    File(at('a.txt')).writeAsStringSync('a');
    Directory(at('Trip')).createSync();
    link = FakeLink();
    transfers = RecordingTransfers(link);
    phone = 'Pocket';
    sharing = true;
    clock = DateTime(2026, 11, 12, 9);
    sender = PcSender(
      link: link,
      transfers: transfers,
      phoneName: () => phone,
      sharingOn: () => sharing,
      turnSharingOn: () => sharing = true,
      temp: () async => Directory(at('temp')),
      linkWait: const Duration(milliseconds: 200),
      now: () => clock,
    );
  });

  tearDown(() async {
    await link.changes.close();
    dir.deleteSync(recursive: true);
  });

  test('files go as they are, folders as zips, the rest not at all', () {
    final files = sender.filesAt([at('a.txt'), at('Trip'), at('missing')]);
    expect(files, hasLength(2));
    expect(files.first, isA<PathFile>());
    expect(files.last, isA<ZippedFolder>());
    expect(files.map((f) => f.name), ['a.txt', 'Trip.zip']);
  });

  test('sends what it can', () async {
    expect(await sender.send([at('a.txt'), at('Trip')]), SendAnswer.sending);
    await Future<void>.delayed(Duration.zero);
    expect(transfers.sent.single, hasLength(2));
  });

  test('nothing to send', () async {
    expect(await sender.send([at('missing')]), SendAnswer.nothing);
    expect(await sender.send([]), SendAnswer.nothing);
    expect(transfers.sent, isEmpty);
  });

  test('no phone paired', () async {
    phone = null;
    expect(await sender.send([at('a.txt')]), SendAnswer.unpaired);
  });

  test('sharing off asks first; turning it on sends', () async {
    sharing = false;
    expect(await sender.send([at('a.txt')]), SendAnswer.off);
    expect(transfers.sent, isEmpty);
    expect(await sender.send([at('a.txt')], turnOn: true), SendAnswer.sending);
    expect(sharing, isTrue);
  });

  test('a phone that is away is said at once once Gotit has run', () async {
    link.up = false;
    clock = clock.add(const Duration(minutes: 5));
    final watch = Stopwatch()..start();
    expect(await sender.send([at('a.txt')]), SendAnswer.away);
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 150)));
  });

  test('just after a start, a send waits for the link', () async {
    link.up = false;
    final answer = sender.send([at('a.txt')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    link
      ..up = true
      ..changes.add(true);
    expect(await answer, SendAnswer.sending);
  });

  test('just after a start, a phone that stays away is said', () async {
    link.up = false;
    expect(await sender.send([at('a.txt')]), SendAnswer.away);
  });

  test('the done callback hears how it ended', () async {
    final done = Completer<SendResult>();
    await sender.send([at('a.txt')], onDone: done.complete);
    expect(await done.future, SendResult.sent);
  });

  group('Send to', () {
    test('reads the files after --send', () async {
      expect(await sendRequest(['--send', 'C:/a b.txt', 'D:/c']), [
        'C:/a b.txt',
        'D:/c',
      ]);
      expect(await sendRequest(['--send']), isEmpty);
      expect(await sendRequest(['--hidden']), isNull);
      expect(await sendRequest([]), isNull);
    });

    test('a long list is handed over through a file, read once', () async {
      final temp = Directory(at('temp'));
      final paths = [for (var i = 0; i < 50; i++) 'C:/folder/file $i.jpg'];
      final args = ['--send', ...paths];
      final handed = await handOverArgs(args, () async => temp, limit: 100);
      expect(handed.first, '--send-list');
      expect(await sendRequest(handed), paths);
      expect(File(handed.last).existsSync(), isFalse);
    });

    test('a short list is handed over as it is', () async {
      final args = ['--send', 'C:/a.txt'];
      expect(await handOverArgs(args, () async => dir), same(args));
    });
  });
}
