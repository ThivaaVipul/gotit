import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';

/// Gotit's mark, "Catch": a ball flying into a C-shaped catch.
///
/// With [tile] it is the app icon, on its slate tile in brand colours. Without
/// it, the glyph alone in the theme's text and accent colours. With [play], the
/// ball flies in once when the mark first appears (unless the system asks for
/// less motion).
class CatchMark extends StatelessWidget {
  const CatchMark({
    this.size = 64,
    this.tile = true,
    this.play = false,
    super.key,
  });

  final double size;
  final bool tile;
  final bool play;

  /// Brand colours, the same as the launcher and Windows icons
  /// (docs/brand/icon.svg).
  static const tileTop = Color(0xFF343B63);
  static const tileBottom = Color(0xFF14161E);
  static const ball = Color(0xFF8F98FF);

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final duration = GotitMotion.of(context).catchIn;
    final animate = play && duration > Duration.zero;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: animate ? 0 : 1, end: 1),
          duration: duration,
          builder: (context, t, _) => CustomPaint(
            painter: _CatchPainter(
              t: t,
              tile: tile,
              glyph: tile ? const Color(0xFFFFFFFF) : colors.fg,
              ball: tile ? ball : colors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatchPainter extends CustomPainter {
  _CatchPainter({
    required this.t,
    required this.tile,
    required this.glyph,
    required this.ball,
  });

  /// Progress of the catch, 0 to 1. At 1 everything is at rest.
  final double t;
  final bool tile;
  final Color glyph;
  final Color ball;

  static double _phase(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is drawn on the icon's 108 by 108 grid.
    final scale = size.shortestSide / 108;
    canvas.scale(scale);

    if (tile) {
      final rect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 108, 108),
        const Radius.circular(108 * 0.26),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.64, -0.84),
            radius: 1.2,
            colors: [CatchMark.tileTop, CatchMark.tileBottom],
            stops: [0, 0.58],
          ).createShader(const Rect.fromLTWH(0, 0, 108, 108)),
      );
      canvas.drawRRect(
        rect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x17FFFFFF),
      );
    }

    // The ball flies in from the right, then the catch gives a little.
    final fly = Curves.easeOutCubic.transform(_phase(t, 0, 0.6));
    final trail = Curves.easeOutCubic.transform(_phase(t, 0.1, 0.7));
    final give = math.sin(math.pi * _phase(t, 0.45, 1)) * 0.07;

    canvas.save();
    canvas.translate(54, 54);
    canvas.scale(1 - give);
    canvas.translate(-54, -54);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(58, 54), radius: 24),
      50 * math.pi / 180,
      260 * math.pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = glyph,
    );
    canvas.restore();

    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = glyph.withValues(alpha: glyph.a * 0.55 * trail);
    final dx = 20 * (1 - trail);
    canvas.drawLine(Offset(71 + dx, 47), Offset(83 + dx, 47), trailPaint);
    canvas.drawLine(Offset(73 + dx, 61), Offset(83 + dx, 61), trailPaint);

    canvas.drawCircle(
      Offset(55 + 34 * (1 - fly), 54),
      9.5,
      Paint()..color = ball.withValues(alpha: ball.a * fly),
    );
  }

  @override
  bool shouldRepaint(_CatchPainter old) =>
      old.t != t || old.tile != tile || old.glyph != glyph || old.ball != ball;
}
