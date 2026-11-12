import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/platform/share_target.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.gotit/share');

  late List<String> calls;

  setUp(() {
    calls = [];
    var pieces = 3;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'read') {
            if (pieces == 0) return null;
            pieces--;
            return Uint8List.fromList([pieces, pieces]);
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('a shared file reads piece by piece, then closes', () async {
    final file = ChannelOutgoingFile.from({
      'handle': 7,
      'name': 'clip.mp4',
      'size': 6,
    })!;
    expect(file.name, 'clip.mp4');
    final pieces = await file.read().toList();
    expect(pieces, [
      [2, 2],
      [1, 1],
      [0, 0],
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['read', 'read', 'read', 'read', 'close']);
  });

  test('a file whose sending stops early still closes', () async {
    final file = ChannelOutgoingFile.from({'handle': 7})!;
    expect(file.name, 'file');
    expect(file.size, -1);
    await file.read().first;
    await Future<void>.delayed(Duration.zero);
    expect(calls.last, 'close');
  });

  test('an item without a handle is no file', () {
    expect(ChannelOutgoingFile.from({'name': 'x'}), isNull);
  });
}
