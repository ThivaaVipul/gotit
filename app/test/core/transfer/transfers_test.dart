import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/core/transfer/folder_store.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// One end of an in-memory link. Sending awaits the other end's handler, as
/// the real link does, so a slow store slows the sender.
class FakeFileLink implements FileLink {
  FakeFileLink? peer;
  bool up = true;
  Future<void> Function(Frame frame)? _handler;

  /// Changes a frame on its way, to test a damaged file.
  Frame Function(Frame frame)? tamper;
  // Closed in tearDown.
  // ignore: close_sinks
  final changes = StreamController<bool>.broadcast();

  @override
  bool get linked => up;

  @override
  Stream<bool> get linkedChanges => changes.stream;

  @override
  set fileFrameHandler(Future<void> Function(Frame frame)? handler) =>
      _handler = handler;

  @override
  Future<bool> sendFileFrame(Frame frame) async {
    if (!up) return false;
    await peer?._handler?.call(tamper?.call(frame) ?? frame);
    return up;
  }

  void drop() {
    up = false;
    changes.add(false);
    peer?.up = false;
    peer?.changes.add(false);
  }
}

class MemoryStore implements FileStore {
  final kept = <String, Uint8List>{};
  int discarded = 0;
  bool full = false;

  @override
  Future<IncomingFile> create(String name, int size) async {
    if (full) throw const FileSystemException('No room');
    return _MemoryFile(this, name);
  }
}

class _MemoryFile implements IncomingFile {
  _MemoryFile(this.store, this.name);

  final MemoryStore store;
  final String name;
  final bytes = BytesBuilder();

  @override
  Future<void> add(List<int> piece) async => bytes.add(piece);

  @override
  Future<ReceivedFile> keep() async {
    store.kept[name] = bytes.takeBytes();
    return ReceivedFile(name: name, location: 'mem:$name', size: 0);
  }

  @override
  Future<void> discard() async => store.discarded++;
}

/// A file to send from memory, in pieces; [gate] holds each piece back.
class MemoryFile implements OutgoingFile {
  MemoryFile(this.name, this.bytes, {this.piece = 100 * 1024, this.gate});

  @override
  final String name;
  final Uint8List bytes;
  final int piece;
  final Future<void> Function(int index)? gate;

  @override
  int get size => bytes.length;

  @override
  Stream<List<int>> read() async* {
    var index = 0;
    for (var at = 0; at < bytes.length; at += piece) {
      await gate?.call(index++);
      yield bytes.sublist(at, min(at + piece, bytes.length));
    }
  }
}

Uint8List _bytes(int length, [int seed = 1]) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

void main() {
  late FakeFileLink phoneEnd;
  late FakeFileLink pcEnd;
  late MemoryStore store;
  late Transfers phone;
  late Transfers pc;
  late List<List<ReceivedFile>> batches;

  setUp(() {
    phoneEnd = FakeFileLink();
    pcEnd = FakeFileLink();
    phoneEnd.peer = pcEnd;
    pcEnd.peer = phoneEnd;
    store = MemoryStore();
    batches = [];
    phone = Transfers(
      link: phoneEnd,
      store: MemoryStore(),
      chunkSize: 64 * 1024,
    )..start();
    pc = Transfers(link: pcEnd, store: store, onBatch: batches.add)..start();
  });

  tearDown(() async {
    await phone.stop();
    await pc.stop();
    await phoneEnd.changes.close();
    await pcEnd.changes.close();
  });

  test('a file arrives whole, checked, under a clean name', () async {
    final bytes = _bytes(300 * 1024);
    final result = await phone.send([MemoryFile('../../notes.txt', bytes)]);
    expect(result, SendResult.sent);
    expect(store.kept['notes.txt'], bytes);
    expect(batches.single.single.name, 'notes.txt');
    expect(phone.value.single.status, TransferStatus.done);
    expect(pc.value.single.status, TransferStatus.done);
    expect(pc.value.single.direction, TransferDirection.receiving);
  });

  test('files sent together arrive as one batch', () async {
    final result = await phone.send([
      MemoryFile('a.jpg', _bytes(10, 1)),
      MemoryFile('b.pdf', _bytes(70 * 1024, 2)),
      MemoryFile('c.txt', _bytes(0, 3)),
    ]);
    expect(result, SendResult.sent);
    expect(batches, hasLength(1));
    expect(batches.single.map((f) => f.name), ['a.jpg', 'b.pdf', 'c.txt']);
    expect(batches.single.first.isImage, isTrue);
    expect(store.kept['c.txt'], isEmpty);
  });

  test('away at once when the other device is not linked', () async {
    phoneEnd.up = false;
    expect(await phone.send([MemoryFile('a.txt', _bytes(5))]), SendResult.away);
    expect(store.kept, isEmpty);
  });

  test('cancel on the sending side drops the half file there', () async {
    late Transfers sender;
    sender = Transfers(
      link: phoneEnd,
      store: MemoryStore(),
      chunkSize: 64 * 1024,
    );
    final file = MemoryFile(
      'big.bin',
      _bytes(500 * 1024),
      gate: (index) async {
        if (index == 2) sender.cancel(sender.value.single.id);
      },
    );
    sender.start();
    expect(await sender.send([file]), SendResult.cancelled);
    expect(store.kept, isEmpty);
    expect(store.discarded, 1);
    expect(pc.value.single.status, TransferStatus.cancelled);
    await sender.stop();
  });

  test('cancel on the receiving side stops the sender', () async {
    final file = MemoryFile(
      'big.bin',
      _bytes(500 * 1024),
      gate: (index) async {
        if (index == 2) pc.cancel(pc.value.single.id);
      },
    );
    expect(await phone.send([file]), SendResult.cancelled);
    expect(store.kept, isEmpty);
    expect(phone.value.single.status, TransferStatus.cancelled);
  });

  test('a damaged file is not kept', () async {
    phoneEnd.tamper = (frame) {
      if (frame.type != Frames.fileChunk) return frame;
      final body = Uint8List.fromList(frame.body!);
      body[0] ^= 0xff;
      return Frame(frame.type, frame.fields, body);
    };
    expect(
      await phone.send([MemoryFile('a.bin', _bytes(1000))]),
      SendResult.sent,
    );
    expect(store.kept, isEmpty);
    expect(store.discarded, 1);
    expect(pc.value.single.status, TransferStatus.failed);
  });

  test('a lost link drops the half file and fails the send', () async {
    final file = MemoryFile(
      'big.bin',
      _bytes(500 * 1024),
      gate: (index) async {
        if (index == 2) phoneEnd.drop();
      },
    );
    expect(await phone.send([file]), SendResult.failed);
    await Future<void>.delayed(Duration.zero);
    expect(store.kept, isEmpty);
    expect(store.discarded, 1);
    expect(pc.value.single.status, TransferStatus.failed);
  });

  test('no room on the receiving side stops the sender', () async {
    store.full = true;
    expect(
      await phone.send([MemoryFile('a.bin', _bytes(200 * 1024))]),
      SendResult.cancelled,
    );
    expect(pc.value.single.status, TransferStatus.failed);
  });

  group('names', () {
    test('only the last part, nothing Windows refuses', () {
      expect(cleanFileName('../../a.txt'), 'a.txt');
      expect(cleanFileName(r'C:\Users\x\report.pdf'), 'report.pdf');
      expect(cleanFileName('a:b?<c>.txt'), 'a_b__c_.txt');
      expect(cleanFileName('con.txt'), '_con.txt');
      expect(cleanFileName('LPT1'), '_LPT1');
      expect(cleanFileName('trailing. . '), 'trailing');
      expect(cleanFileName('..'), 'file');
      expect(cleanFileName(null), 'file');
      expect(cleanFileName('.gitignore'), '.gitignore');
    });

    test('a very long name keeps its extension', () {
      final name = cleanFileName('${'x' * 300}.jpeg');
      expect(name.length, 150);
      expect(name, endsWith('.jpeg'));
    });
  });

  group('the folder', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('gotit_files_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'a kept file takes a free name; a discarded one leaves nothing',
      () async {
        File(
          '${dir.path}${Platform.pathSeparator}photo.jpg',
        ).writeAsStringSync('old');
        final folder = FolderStore(() async => dir);

        final first = await folder.create('photo.jpg', 3);
        await first.add([1, 2, 3]);
        final kept = await first.keep();
        expect(kept.name, 'photo (1).jpg');
        expect(File(kept.location).readAsBytesSync(), [1, 2, 3]);

        final second = await folder.create('photo.jpg', 3);
        await second.add([4]);
        await second.discard();
        await second.discard();
        expect(dir.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
          'photo.jpg',
          'photo (1).jpg',
        });
      },
    );

    test('a file on disk reads back as it is', () async {
      final path = '${dir.path}${Platform.pathSeparator}a.bin';
      File(path).writeAsBytesSync(_bytes(1000));
      final file = PathFile(path);
      expect(file.name, 'a.bin');
      expect(file.size, 1000);
      final read = await file.read().expand((piece) => piece).toList();
      expect(read, _bytes(1000));
    });
  });
}
