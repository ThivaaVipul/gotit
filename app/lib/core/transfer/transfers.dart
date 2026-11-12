import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

/// The link, as far as files are concerned.
abstract interface class FileLink {
  bool get linked;
  Stream<bool> get linkedChanges;

  /// Sends a file frame and waits until it has left. False when not linked.
  Future<bool> sendFileFrame(Frame frame);

  /// Handles the other side's file frames, one at a time and awaited, so a
  /// slow disk here slows the sender down.
  set fileFrameHandler(Future<void> Function(Frame frame)? handler);
}

/// A file to send.
abstract interface class OutgoingFile {
  String get name;

  /// In bytes, or -1 when unknown.
  int get size;

  /// Its bytes in pieces of any size, read only as fast as they are sent.
  Stream<List<int>> read();
}

/// Where arriving files are kept.
abstract interface class FileStore {
  /// Starts a file to be called [name], which is already safe to use.
  /// Throws when it can't be written (no room, no access).
  Future<IncomingFile> create(String name, int size);
}

/// Refuses every file, so the sender stops at once: while sharing is off,
/// or where receiving isn't built yet.
class GatedStore implements FileStore {
  GatedStore(this.inner, {required this.open});

  final FileStore? inner;

  /// Whether files may arrive now.
  final bool Function() open;

  @override
  Future<IncomingFile> create(String name, int size) {
    final store = inner;
    if (store == null || !open()) {
      throw StateError('Not taking files now');
    }
    return store.create(name, size);
  }
}

/// A file being received.
abstract interface class IncomingFile {
  Future<void> add(List<int> bytes);

  /// Keeps it under its final name, made unique ("name (1).ext").
  Future<ReceivedFile> keep();

  /// Throws away what arrived. Safe to call more than once.
  Future<void> discard();
}

/// A file that arrived and was kept.
@immutable
class ReceivedFile {
  const ReceivedFile({
    required this.name,
    required this.location,
    required this.size,
  });

  final String name;

  /// Where it is: a path on the PC, a content URI on the phone.
  final String location;
  final int size;

  bool get isImage => _imageExtensions.contains(extensionOf(name));
}

const _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
};

/// The extension of [name], lower case and without the dot.
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// A file name from the other device, made safe: only its last part, so it
/// can't leave the folder, without characters Windows refuses, not a name
/// Windows reserves, and not too long.
String cleanFileName(String? raw) {
  var name = (raw ?? '').split(RegExp(r'[\\/]')).last;
  name = name.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
  // Windows drops trailing dots and spaces itself; "." and ".." vanish here.
  name = name.replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) return 'file';
  final stem = name.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    name = '_$name';
  }
  const longest = 150;
  if (name.length > longest) {
    final extension = extensionOf(name);
    final tail = extension.isEmpty || extension.length > 20
        ? ''
        : '.$extension';
    name = name.substring(0, longest - tail.length) + tail;
  }
  return name;
}

enum TransferDirection { sending, receiving }

enum TransferStatus { running, done, failed, cancelled }

/// One file on its way, either way.
@immutable
class Transfer {
  const Transfer({
    required this.id,
    required this.name,
    required this.size,
    required this.direction,
    this.bytes = 0,
    this.status = TransferStatus.running,
    this.location,
  });

  final String id;
  final String name;

  /// In bytes, or -1 when unknown.
  final int size;
  final TransferDirection direction;

  /// How much has gone or arrived.
  final int bytes;
  final TransferStatus status;

  /// Where a received file was kept.
  final String? location;

  /// From 0 to 1, or null while the size is unknown.
  double? get progress => size > 0 ? (bytes / size).clamp(0.0, 1.0) : null;

  bool get running => status == TransferStatus.running;

  Transfer copyWith({
    String? name,
    int? bytes,
    TransferStatus? status,
    String? location,
  }) => Transfer(
    id: id,
    name: name ?? this.name,
    size: size,
    direction: direction,
    bytes: bytes ?? this.bytes,
    status: status ?? this.status,
    location: location ?? this.location,
  );
}

/// What became of a send.
enum SendResult { sent, away, failed, cancelled }

/// Sends and receives files over the link, one at a time each way, in
/// 256 KiB pieces with a SHA-256 of the whole file, which the receiver checks
/// before keeping it. Nothing is queued across a lost link: what was on its
/// way fails, and a half-received file is thrown away.
class Transfers extends ValueNotifier<List<Transfer>> {
  Transfers({
    required this.link,
    required this.store,
    this.onBatch,
    this.chunkSize = 256 * 1024,
    this.keepFinished = const Duration(seconds: 30),
    this.progressEvery = const Duration(milliseconds: 200),
    Random? random,
  }) : _random = random ?? Random.secure(),
       super(const []);

  final FileLink link;
  final FileStore store;

  /// Files sent together have arrived, or as many as will.
  final void Function(List<ReceivedFile> files)? onBatch;
  final int chunkSize;

  /// How long a finished transfer stays listed.
  final Duration keepFinished;

  /// At most one progress update per this, so a fast transfer doesn't flood
  /// the screen or the notification.
  final Duration progressEvery;
  final Random _random;

  final _incoming = <String, _Incoming>{};
  final _batches = <String, List<ReceivedFile>>{};
  final _stopped = <String>{};
  final _shownAt = <String, DateTime>{};
  final _clearing = <Timer>[];
  StreamSubscription<bool>? _linkWatch;
  Future<void> _sending = Future.value();

  void start() {
    link.fileFrameHandler = _onFrame;
    _linkWatch = link.linkedChanges.listen((linked) {
      if (!linked) unawaited(_linkLost());
    });
  }

  Future<void> stop() async {
    link.fileFrameHandler = null;
    await _linkWatch?.cancel();
    await _linkLost();
    for (final timer in _clearing) {
      timer.cancel();
    }
  }

  /// Sends [files] one after another: [SendResult.away] at once when the
  /// other device isn't linked. A send waits for the one before it.
  Future<SendResult> send(List<OutgoingFile> files) {
    final turn = _sending.then((_) => _sendAll(files));
    _sending = turn.then((_) {}, onError: (Object _) {});
    return turn;
  }

  /// Stops a file, whichever way it is going.
  void cancel(String id) {
    final incoming = _incoming.remove(id);
    if (incoming == null) {
      // One being sent stops at its next piece.
      _stopped.add(id);
      return;
    }
    unawaited(incoming.file.discard());
    unawaited(link.sendFileFrame(Frame(Frames.fileCancel, {'id': id})));
    _end(id, TransferStatus.cancelled);
    _batchEnded(incoming);
  }

  // Sending --------------------------------------------------------------

  Future<SendResult> _sendAll(List<OutgoingFile> files) async {
    if (files.isEmpty) return SendResult.sent;
    if (!link.linked) return SendResult.away;
    final batch = _newId();
    for (var i = 0; i < files.length; i++) {
      final result = await _sendOne(files[i], batch, i, files.length);
      if (result != SendResult.sent) return result;
    }
    return SendResult.sent;
  }

  Future<SendResult> _sendOne(
    OutgoingFile file,
    String batch,
    int index,
    int count,
  ) async {
    final id = _newId();
    _put(
      Transfer(
        id: id,
        name: file.name,
        size: file.size,
        direction: TransferDirection.sending,
      ),
    );
    final offered = await link.sendFileFrame(
      Frame(Frames.fileOffer, {
        'id': id,
        'name': file.name,
        'size': file.size,
        'batch': batch,
        'index': index,
        'count': count,
      }),
    );
    if (!offered) {
      _end(id, TransferStatus.failed);
      return SendResult.away;
    }
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    var sent = 0;
    try {
      await for (final piece in file.read()) {
        for (var at = 0; at < piece.length; at += chunkSize) {
          if (_stopped.remove(id)) return _cancelled(id);
          final part = Uint8List.fromList(
            piece.sublist(at, min(at + chunkSize, piece.length)),
          );
          hash.add(part);
          final went = await link.sendFileFrame(
            Frame(Frames.fileChunk, {'id': id}, part),
          );
          if (!went) {
            _end(id, TransferStatus.failed);
            return SendResult.failed;
          }
          sent += part.length;
          _progress(id, sent);
        }
      }
    } on Object {
      // The file couldn't be read: the other side drops what it has.
      unawaited(link.sendFileFrame(Frame(Frames.fileCancel, {'id': id})));
      _end(id, TransferStatus.failed);
      return SendResult.failed;
    }
    if (_stopped.remove(id)) return _cancelled(id);
    hash.close();
    final finished = await link.sendFileFrame(
      Frame(Frames.fileDone, {'id': id, 'sha256': digest.value.toString()}),
    );
    if (!finished) {
      _end(id, TransferStatus.failed);
      return SendResult.failed;
    }
    _end(id, TransferStatus.done, bytes: sent);
    return SendResult.sent;
  }

  Future<SendResult> _cancelled(String id) async {
    await link.sendFileFrame(Frame(Frames.fileCancel, {'id': id}));
    _end(id, TransferStatus.cancelled);
    return SendResult.cancelled;
  }

  // Receiving ------------------------------------------------------------

  Future<void> _onFrame(Frame frame) async {
    final id = frame.text('id');
    if (id == null) return;
    switch (frame.type) {
      case Frames.fileOffer:
        await _offered(id, frame);
      case Frames.fileChunk:
        await _piece(id, frame.body);
      case Frames.fileDone:
        await _finished(id, frame.text('sha256'));
      case Frames.fileCancel:
        // Ours, being sent: stop. Theirs, arriving: drop it.
        _stopped.add(id);
        final incoming = _incoming.remove(id);
        if (incoming != null) {
          await incoming.file.discard();
          _end(id, TransferStatus.cancelled);
          _batchEnded(incoming);
        }
    }
  }

  Future<void> _offered(String id, Frame frame) async {
    if (_incoming.containsKey(id)) return;
    final name = cleanFileName(frame.text('name'));
    final size = frame.number('size') ?? -1;
    final batch = frame.text('batch') ?? id;
    final IncomingFile file;
    try {
      file = await store.create(name, size);
    } on Object {
      // No room, or nowhere to write: the sender stops.
      unawaited(link.sendFileFrame(Frame(Frames.fileCancel, {'id': id})));
      _put(
        Transfer(
          id: id,
          name: name,
          size: size,
          direction: TransferDirection.receiving,
          status: TransferStatus.failed,
        ),
      );
      _clearLater(id);
      return;
    }
    _incoming[id] = _Incoming(
      file: file,
      batch: batch,
      index: frame.number('index') ?? 0,
      count: frame.number('count') ?? 1,
      size: size,
    );
    _put(
      Transfer(
        id: id,
        name: name,
        size: size,
        direction: TransferDirection.receiving,
      ),
    );
  }

  Future<void> _piece(String id, Uint8List? body) async {
    final incoming = _incoming[id];
    if (incoming == null || body == null) return;
    incoming.received += body.length;
    if (incoming.size >= 0 && incoming.received > incoming.size) {
      await _fail(id, incoming);
      return;
    }
    try {
      await incoming.file.add(body);
    } on Object {
      await _fail(id, incoming);
      return;
    }
    incoming.hash.add(body);
    _progress(id, incoming.received);
  }

  Future<void> _finished(String id, String? sha) async {
    final incoming = _incoming.remove(id);
    if (incoming == null) return;
    incoming.hash.close();
    final whole =
        sha != null &&
        incoming.digest.value.toString() == sha &&
        (incoming.size < 0 || incoming.received == incoming.size);
    if (!whole) {
      await incoming.file.discard();
      _end(id, TransferStatus.failed);
      _batchEnded(incoming);
      return;
    }
    final ReceivedFile kept;
    try {
      kept = await incoming.file.keep();
    } on Object {
      await incoming.file.discard();
      _end(id, TransferStatus.failed);
      _batchEnded(incoming);
      return;
    }
    _end(
      id,
      TransferStatus.done,
      bytes: incoming.received,
      name: kept.name,
      location: kept.location,
    );
    final files = _batches.putIfAbsent(incoming.batch, () => []);
    files.add(kept);
    if (incoming.index >= incoming.count - 1) _batchEnded(incoming);
  }

  /// Drops a file that went wrong here and tells the sender to stop.
  Future<void> _fail(String id, _Incoming incoming) async {
    if (!identical(_incoming[id], incoming)) return;
    _incoming.remove(id);
    await incoming.file.discard();
    unawaited(link.sendFileFrame(Frame(Frames.fileCancel, {'id': id})));
    _end(id, TransferStatus.failed);
    _batchEnded(incoming);
  }

  /// The rest of a batch won't come: hand over what did.
  void _batchEnded(_Incoming incoming) {
    final files = _batches.remove(incoming.batch);
    if (files != null && files.isNotEmpty) {
      onBatch?.call(List.unmodifiable(files));
    }
  }

  Future<void> _linkLost() async {
    final lost = Map.of(_incoming);
    _incoming.clear();
    for (final MapEntry(key: id, value: incoming) in lost.entries) {
      await incoming.file.discard();
      _end(id, TransferStatus.failed);
      _batchEnded(incoming);
    }
  }

  // The list ---------------------------------------------------------------

  void _put(Transfer transfer) {
    final list = [...value];
    final at = list.indexWhere((t) => t.id == transfer.id);
    if (at < 0) {
      list.add(transfer);
    } else {
      list[at] = transfer;
    }
    value = List.unmodifiable(list);
  }

  Transfer? _find(String id) {
    for (final transfer in value) {
      if (transfer.id == id) return transfer;
    }
    return null;
  }

  void _progress(String id, int bytes) {
    final now = DateTime.now();
    final last = _shownAt[id];
    if (last != null && now.difference(last) < progressEvery) return;
    _shownAt[id] = now;
    final transfer = _find(id);
    if (transfer != null && transfer.running) {
      _put(transfer.copyWith(bytes: bytes));
    }
  }

  void _end(
    String id,
    TransferStatus status, {
    int? bytes,
    String? name,
    String? location,
  }) {
    _shownAt.remove(id);
    final transfer = _find(id);
    if (transfer == null) return;
    _put(
      transfer.copyWith(
        status: status,
        bytes: bytes,
        name: name,
        location: location,
      ),
    );
    _clearLater(id);
  }

  void _clearLater(String id) {
    _clearing.add(
      Timer(keepFinished, () {
        final list = value.where((t) => t.id != id || t.running).toList();
        if (list.length != value.length) value = List.unmodifiable(list);
      }),
    );
  }

  String _newId() => List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class _Incoming {
  _Incoming({
    required this.file,
    required this.batch,
    required this.index,
    required this.count,
    required this.size,
  }) {
    hash = sha256.startChunkedConversion(digest);
  }

  final IncomingFile file;
  final String batch;
  final int index;
  final int count;
  final int size;
  // Only holds the result; closing it does nothing.
  // ignore: close_sinks
  final digest = _DigestSink();
  // Closed when the file is complete, in Transfers._finished.
  // ignore: close_sinks
  late final ByteConversionSink hash;
  int received = 0;
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
