import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/app/widgets/catch_mark.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: gotitTheme(Brightness.dark),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('plays the catch once, then rests', (tester) async {
    await tester.pumpWidget(_app(const CatchMark(play: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('stays still when the system asks for less motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const CatchMark(play: true), reduceMotion: true),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('is decorative for screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(const CatchMark(size: 40, tile: false)));
    expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    semantics.dispose();
  });
}
