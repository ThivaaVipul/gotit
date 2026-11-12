import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/platform/phone_downloads.dart';
import 'package:gotit/core/transfer/transfers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.gotit/received');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late bool writes;

  setUp(() {
    calls = [];
    writes = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'create' => 4,
        'write' => writes,
        'keep' => {
          'uri': 'content://media/external/downloads/9',
          'name': 'photo (1).jpg',
        },
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<Object?, Object?> args(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  test('a file is written piece by piece, then kept as named', () async {
    final file = await PhoneDownloads().create('photo.jpg', 5);
    await file.add([1, 2]);
    await file.add([3, 4, 5]);
    final kept = await file.keep();
    expect(calls.map((c) => c.method), ['create', 'write', 'write', 'keep']);
    expect(args(calls.first), {'name': 'photo.jpg', 'size': 5});
    expect(args(calls[1])['bytes'], [1, 2]);
    expect(args(calls[1])['handle'], 4);
    expect(kept.name, 'photo (1).jpg');
    expect(kept.location, 'content://media/external/downloads/9');
    expect(kept.size, 5);
  });

  test('a write that fails throws, and the file is deleted once', () async {
    final file = await PhoneDownloads().create('a.bin', 10);
    writes = false;
    await expectLater(file.add([1]), throwsStateError);
    await file.discard();
    await file.discard();
    expect(calls.where((c) => c.method == 'discard'), hasLength(1));
  });

  test('a single image also goes on the clipboard', () async {
    const photo = ReceivedFile(name: 'a.jpg', location: 'content://1', size: 1);
    const pdf = ReceivedFile(name: 'b.pdf', location: 'content://2', size: 1);
    final downloads = PhoneDownloads();
    await downloads.arrived([photo], from: 'Desk PC');
    await downloads.arrived([pdf], from: 'Desk PC');
    await downloads.arrived([photo, photo], from: 'Desk PC');
    expect(calls.map((c) => args(c)['clip']), [true, false, false]);
    expect(args(calls.first)['from'], 'Desk PC');
    expect(args(calls.first)['files'], [
      {'uri': 'content://1', 'name': 'a.jpg'},
    ]);
  });
}
