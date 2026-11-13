import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:gotit/core/transfer/transfers.dart';

/// Keeps arriving files in a folder (the PC's `Downloads\Gotit`). Each one is
/// written to a `.gotit-part` file first and takes its real name only once
/// it arrived whole, so a half file never looks like a finished one.
class FolderStore implements FileStore {
  FolderStore(this.folder, {Random? random})
    : _random = random ?? Random.secure();

  /// The folder, made when the first file arrives.
  final Future<Directory> Function() folder;
  final Random _random;

  @override
  Future<IncomingFile> create(String name, int size) async {
    final dir = await folder();
    await dir.create(recursive: true);
    final tag = _random.nextInt(1 << 32).toRadixString(16);
    final part = File(_join(dir.path, '$name.$tag.gotit-part'));
    return _FolderFile(dir, name, part, part.openWrite());
  }
}

class _FolderFile implements IncomingFile {
  _FolderFile(this._dir, this._name, this._part, this._sink);

  final Directory _dir;
  final String _name;
  final File _part;
  final IOSink _sink;
  bool _closed = false;
  int _size = 0;

  @override
  Future<void> add(List<int> bytes) async {
    if (_closed) throw StateError('Closed');
    _sink.add(bytes);
    _size += bytes.length;
    // Written before the next piece is read off the link.
    await _sink.flush();
  }

  @override
  Future<ReceivedFile> keep() async {
    await _close();
    final target = uniqueFile(_dir, _name);
    await _part.rename(target.path);
    return ReceivedFile(
      name: target.uri.pathSegments.last,
      location: target.path,
      size: _size,
    );
  }

  @override
  Future<void> discard() async {
    await _close();
    try {
      if (await _part.exists()) await _part.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sink.close();
    } on Object {
      // Closing anyway.
    }
  }
}

/// [name] in [dir], or "name (1).ext", "name (2).ext" when taken.
File uniqueFile(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  var candidate = File(_join(dir.path, name));
  for (var n = 1; candidate.existsSync(); n++) {
    candidate = File(_join(dir.path, '$stem ($n)$extension'));
  }
  return candidate;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// A file on disk to send.
class PathFile implements OutgoingFile {
  PathFile(this.path);

  final String path;

  @override
  String get name => File(path).uri.pathSegments.last;

  @override
  int get size {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return -1;
    }
  }

  @override
  Stream<List<int>> read() => File(path).openRead();

  @override
  String? get source => path;
}
