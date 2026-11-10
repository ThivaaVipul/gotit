import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:gotit/core/link/identity.dart';
import 'package:win32/win32.dart';

/// Locks bytes so only this user on this device can unlock them.
abstract interface class Sealer {
  Future<Uint8List> seal(Uint8List plain);
  Future<Uint8List> open(Uint8List sealed);
}

/// Secrets as sealed files in the app's own folder: one file per secret.
class SealedFileSecrets implements SecretStore {
  SealedFileSecrets(this._dir, this._sealer);

  final Directory _dir;
  final Sealer _sealer;

  File _file(String key) =>
      File('${_dir.path}${Platform.pathSeparator}$key.sealed');

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    try {
      return utf8.decode(await _sealer.open(await file.readAsBytes()));
    } on Object {
      // Sealed by another user or device, or damaged: as good as missing.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    await _dir.create(recursive: true);
    final sealed = await _sealer.seal(Uint8List.fromList(utf8.encode(value)));
    final temp = File('${_file(key).path}.tmp');
    await temp.writeAsBytes(sealed, flush: true);
    await temp.rename(_file(key).path);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }
}

/// Windows: DPAPI, tied to the signed-in user.
class WindowsSealer implements Sealer {
  const WindowsSealer();

  /// Never show a prompt: fail instead.
  static const _uiForbidden = 0x1;

  @override
  Future<Uint8List> seal(Uint8List plain) async => _run(plain, protect: true);

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      _run(sealed, protect: false);

  static Uint8List _run(Uint8List data, {required bool protect}) =>
      using((arena) {
        final buffer = arena<Uint8>(data.isEmpty ? 1 : data.length);
        buffer.asTypedList(data.length).setAll(0, data);
        final input = arena<CRYPT_INTEGER_BLOB>();
        input.ref
          ..cbData = data.length
          ..pbData = buffer;
        final output = arena<CRYPT_INTEGER_BLOB>();
        final done = protect
            ? CryptProtectData(input, null, null, null, _uiForbidden, output)
            : CryptUnprotectData(input, null, null, null, _uiForbidden, output);
        if (!done.value) {
          throw WindowsException(done.error.toHRESULT());
        }
        try {
          return Uint8List.fromList(
            output.ref.pbData.asTypedList(output.ref.cbData),
          );
        } finally {
          LocalFree(HLOCAL(output.ref.pbData));
        }
      });
}

/// Android: an AES key that never leaves the Android Keystore
/// (MainActivity's `seal` and `open`).
class AndroidSealer implements Sealer {
  const AndroidSealer();

  static const _channel = MethodChannel('app.gotit/device');

  @override
  Future<Uint8List> seal(Uint8List plain) async =>
      (await _channel.invokeMethod<Uint8List>('seal', plain))!;

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      (await _channel.invokeMethod<Uint8List>('open', sealed))!;
}
