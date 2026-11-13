import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// A folder to send, zipped first into its own temporary folder, which goes
/// once the send is over. The zip holds the folder itself, as Windows' own
/// "Compressed (zipped) folder" does. Zipping runs in its own isolate, so the
/// window stays smooth and Cancel can stop it at once.
class ZippedFolder implements PreparedFile {
  ZippedFolder(this.path, {required this.temp});

  /// The folder.
  final String path;

  /// Where zips are made: a folder of Gotit's own, cleared at start.
  final Future<Directory> Function() temp;

  Directory? _work;
  File? _zip;
  Isolate? _isolate;
  bool _stopped = false;

  @override
  String get name => '${folderName(path)}.zip';

  @override
  String? get source => path;

  @override
  int get size {
    try {
      return _zip?.lengthSync() ?? -1;
    } on FileSystemException {
      return -1;
    }
  }

  @override
  Future<void> prepare() async {
    final root = await temp();
    await root.create(recursive: true);
    final work = _work = await root.createTemp('zip-');
    final target = '${work.path}${Platform.pathSeparator}$name';
    if (_stopped) throw StateError('Stopped');
    final done = ReceivePort();
    try {
      final isolate = _isolate = await Isolate.spawn(
        _zipInIsolate,
        (path, target, done.sendPort),
        onExit: done.sendPort,
        onError: done.sendPort,
      );
      if (_stopped) isolate.kill(priority: Isolate.immediate);
      // True when zipped; an error, or nothing from a stopped isolate,
      // otherwise.
      if (await done.first != true) throw StateError('Not zipped');
    } finally {
      done.close();
      _isolate = null;
    }
    _zip = File(target);
  }

  @override
  void stop() {
    _stopped = true;
    _isolate?.kill(priority: Isolate.immediate);
  }

  @override
  Stream<List<int>> read() {
    final zip = _zip;
    if (zip == null) return Stream.error(StateError('Not zipped'));
    return zip.openRead();
  }

  @override
  Future<void> dispose() async {
    final work = _work;
    _work = null;
    _zip = null;
    if (work == null) return;
    try {
      await work.delete(recursive: true);
    } on FileSystemException {
      // Cleared at the next start.
    }
  }
}

Future<void> _zipInIsolate((String, String, SendPort) job) async {
  final (folder, target, done) = job;
  await zipFolder(folder, target);
  done.send(true);
}

/// Zips [folder] into [target], with the folder at the top. Files that are
/// compressed already (photos, videos, music, archives) are stored as they
/// are, which is quicker and no bigger; the rest are deflated.
Future<void> zipFolder(String folder, String target) async {
  final dir = Directory(folder);
  final top = folderName(folder);
  final base = dir.absolute.path.replaceAll(RegExp(r'[\\/]+$'), '');
  final entries = dir.absolute.listSync(recursive: true, followLinks: false);
  final encoder = ZipFileEncoder()..create(target);
  try {
    if (entries.isEmpty) encoder.addArchiveFile(ArchiveFile.directory(top));
    for (final entry in entries) {
      final inside = entry.path
          .substring(base.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp('^/+'), '');
      final name = '$top/$inside';
      if (entry is Directory) {
        encoder.addArchiveFile(ArchiveFile.directory(name));
      } else if (entry is File) {
        await encoder.addFile(
          entry,
          name,
          _compressed.contains(extensionOf(entry.path))
              ? ZipFileEncoder.store
              : ZipFileEncoder.gzip,
        );
      }
    }
  } finally {
    await encoder.close();
  }
}

/// The last part of [path], or "folder" for a drive or an empty name.
String folderName(String path) {
  final last = path
      .replaceAll(RegExp(r'[\\/]+$'), '')
      .split(RegExp(r'[\\/]'))
      .last;
  return last.isEmpty || last.endsWith(':') ? 'folder' : last;
}

const _compressed = {
  // Pictures.
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif',
  // Video and sound.
  'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp',
  'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac',
  // Archives, and documents that are zips inside.
  'zip', 'rar', '7z', 'gz', 'tgz', 'bz2', 'xz', 'zst',
  'apk', 'jar', 'docx', 'xlsx', 'pptx', 'odt', 'ods', 'odp',
};
