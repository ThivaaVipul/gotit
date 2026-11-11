import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/features/home/widgets/sharing_row.dart';

class _QuietLink implements SharingLink {
  final sent = <SharingState>[];

  @override
  bool sendSharing(SharingState state) {
    sent.add(state);
    return true;
  }

  @override
  Stream<SharingState> get sharingChanges => const Stream.empty();

  @override
  bool get linked => true;

  @override
  Stream<bool> get linkedChanges => const Stream.empty();
}

const _pc = Peer(id: 'pc', name: 'Desk PC', certPem: 'x');

void main() {
  late Directory dir;
  late SettingsStore settings;
  late _QuietLink link;
  late SharingSwitch sharing;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('gotit_sharing_row_');
    settings = await SettingsStore.open(File('${dir.path}/settings.json'));
    link = _QuietLink();
    sharing = SharingSwitch(
      initial: SharingState.initial,
      deviceId: 'phone',
      link: link,
      save: (_) async {},
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: gotitTheme(Brightness.dark),
      home: Scaffold(
        body: SharingRow(sharing: sharing, settings: settings),
      ),
    ),
  );

  testWidgets('hidden until paired', (tester) async {
    await show(tester);
    expect(find.text('Sharing'), findsNothing);
  });

  testWidgets('turns sharing off and on for both devices', (tester) async {
    settings.value = const Settings(peer: _pc);
    await show(tester);
    expect(find.text('Copies cross both ways'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(sharing.on, isFalse);
    expect(link.sent.single.on, isFalse);
    expect(find.text('Paused on both devices'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(sharing.on, isTrue);
    expect(find.text('Copies cross both ways'), findsOneWidget);
  });
}
