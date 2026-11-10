import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/platform/secrets.dart';

/// Flips every bit: enough to show the file never holds the plain text.
class FlipSealer implements Sealer {
  @override
  Future<Uint8List> seal(Uint8List plain) async =>
      Uint8List.fromList([for (final b in plain) b ^ 0xFF]);

  @override
  Future<Uint8List> open(Uint8List sealed) => seal(sealed);
}

class BrokenSealer extends FlipSealer {
  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      throw const FormatException('not ours');
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('gotit_secrets_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps a secret sealed on disk and opens it again', () async {
    final secrets = SealedFileSecrets(dir, FlipSealer());
    await secrets.write('identity', 'top secret');
    final onDisk = File('${dir.path}/identity.sealed').readAsBytesSync();
    expect(
      utf8.decode(onDisk, allowMalformed: true),
      isNot(contains('top secret')),
    );
    expect(await secrets.read('identity'), 'top secret');
  });

  test('a missing or unopenable secret reads as nothing', () async {
    expect(await SealedFileSecrets(dir, FlipSealer()).read('identity'), isNull);
    await SealedFileSecrets(dir, FlipSealer()).write('identity', 'x');
    expect(
      await SealedFileSecrets(dir, BrokenSealer()).read('identity'),
      isNull,
    );
  });

  test('delete removes it', () async {
    final secrets = SealedFileSecrets(dir, FlipSealer());
    await secrets.write('identity', 'x');
    await secrets.delete('identity');
    expect(await secrets.read('identity'), isNull);
  });

  test(
    'DPAPI seals and opens for this user',
    () async {
      const sealer = WindowsSealer();
      final plain = Uint8List.fromList(utf8.encode('-----BEGIN KEY-----'));
      final sealed = await sealer.seal(plain);
      expect(sealed, isNot(plain));
      expect(await sealer.open(sealed), plain);
    },
    skip: Platform.isWindows ? false : 'DPAPI is Windows only',
  );
}
