import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gotit/core/transfer/transfers.dart';

const _channel = MethodChannel('app.gotit/received');

/// The phone's `Download/Gotit`, through MediaStore in Kotlin. Files are
/// written straight there, hidden until they arrived whole and deleted if
/// they didn't; MediaStore makes a clashing name unique ("name (1).ext").
class PhoneDownloads implements FileStore {
  @override
  Future<IncomingFile> create(String name, int size) async {
    final handle = await _channel.invokeMethod<int>('create', {
      'name': name,
      'size': size,
    });
    if (handle == null) throw StateError('Not created');
    return _PhoneDownload(handle, name);
  }

  /// [files] arrived from [from]: a notice with Open and Share, and a single
  /// image also on the clipboard.
  Future<void> arrived(List<ReceivedFile> files, {required String from}) async {
    try {
      await _channel.invokeMethod<void>('arrived', {
        'from': from,
        'files': [
          for (final file in files) {'uri': file.location, 'name': file.name},
        ],
        'clip': files.length == 1 && files.single.isImage,
      });
    } on PlatformException {
      // The files are there anyway, in Download/Gotit.
    }
  }
}

/// Opens a received file (a content URI) with its usual app.
void openOnPhone(String location) =>
    unawaited(_channel.invokeMethod<void>('open', {'uri': location}));

class _PhoneDownload implements IncomingFile {
  _PhoneDownload(this.handle, this.name);

  final int handle;
  final String name;
  int _size = 0;
  bool _discarded = false;

  @override
  Future<void> add(List<int> bytes) async {
    final written = await _channel.invokeMethod<bool>('write', {
      'handle': handle,
      'bytes': bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    });
    if (written != true) throw StateError('Not written');
    _size += bytes.length;
  }

  @override
  Future<ReceivedFile> keep() async {
    final kept = await _channel.invokeMapMethod<String, Object?>('keep', {
      'handle': handle,
    });
    final uri = kept?['uri'];
    final keptName = kept?['name'];
    if (uri is! String || uri.isEmpty) throw StateError('Not kept');
    return ReceivedFile(
      name: keptName is String && keptName.isNotEmpty ? keptName : name,
      location: uri,
      size: _size,
    );
  }

  @override
  Future<void> discard() async {
    if (_discarded) return;
    _discarded = true;
    try {
      await _channel.invokeMethod<void>('discard', {'handle': handle});
    } on PlatformException {
      // Gone already; MediaStore drops a hidden file left behind in a week.
    }
  }
}
