import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/link/peer.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/features/home/cubit/link_cubits.dart';
import 'package:gotit/features/home/widgets/link_hero.dart';

const _pc = Peer(id: 'pc', name: 'Desk PC', certPem: 'x');

Future<void> _show(WidgetTester tester, PhoneLinkState state) =>
    tester.pumpWidget(
      MaterialApp(
        theme: gotitTheme(Brightness.dark),
        home: Scaffold(
          body: BlocProvider(
            create: (_) => PhoneLinkCubit(state, const Stream.empty()),
            child: const PhoneLinkHero(),
          ),
        ),
      ),
    );

void main() {
  testWidgets('connected', (tester) async {
    await _show(
      tester,
      const PhoneLinkState(pc: _pc, connection: Connection.online),
    );
    expect(find.text('Desk PC'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('looking for the PC', (tester) async {
    await _show(
      tester,
      const PhoneLinkState(pc: _pc, connection: Connection.connecting),
    );
    expect(find.text('Looking for Desk PC'), findsOneWidget);
  });

  testWidgets('an older PC needs updating', (tester) async {
    await _show(
      tester,
      const PhoneLinkState(
        pc: _pc,
        connection: Connection.mismatch,
        theirVersion: LinkSpec.version - 1,
      ),
    );
    expect(find.text('Update Gotit on Desk PC'), findsOneWidget);
  });

  testWidgets('a newer PC means this phone needs updating', (tester) async {
    await _show(
      tester,
      const PhoneLinkState(
        pc: _pc,
        connection: Connection.mismatch,
        theirVersion: LinkSpec.version + 1,
      ),
    );
    expect(find.text('Update Gotit on this phone'), findsOneWidget);
  });
}
