import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';

void main() {
  test('light and dark themes carry the Slate palette', () {
    final light = gotitTheme(Brightness.light);
    final dark = gotitTheme(Brightness.dark);
    expect(light.scaffoldBackgroundColor, GotitColors.light.bg);
    expect(dark.scaffoldBackgroundColor, GotitColors.dark.bg);
    expect(light.colorScheme.primary, GotitColors.light.accent);
    expect(dark.colorScheme.primary, GotitColors.dark.accent);
    expect(light.extension<GotitColors>(), GotitColors.light);
    expect(dark.extension<GotitMotion>(), GotitMotion.standard);
  });

  test('text is set in Inter, small print in the muted colour', () {
    final theme = gotitTheme(Brightness.light);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(theme.textTheme.headlineMedium?.fontFamily, 'Inter');
    expect(theme.textTheme.bodyMedium?.color, GotitColors.light.fg);
    expect(theme.textTheme.bodySmall?.color, GotitColors.light.muted);
  });

  testWidgets('motion stops when the system asks for less', (tester) async {
    late GotitMotion normal;
    late GotitMotion reduced;
    await tester.pumpWidget(
      MaterialApp(
        theme: gotitTheme(Brightness.light),
        home: Column(
          children: [
            Builder(
              builder: (context) {
                normal = GotitMotion.of(context);
                return const SizedBox();
              },
            ),
            MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  reduced = GotitMotion.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
    expect(normal.enter, const Duration(milliseconds: 280));
    expect(reduced.enter, Duration.zero);
    expect(reduced.cross, Duration.zero);
  });
}
