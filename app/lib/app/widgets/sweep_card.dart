import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';

/// A card whose border carries a slow sweep of light while [live]: the
/// connected look.
class SweepCard extends StatefulWidget {
  const SweepCard({
    required this.child,
    this.live = false,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final bool live;
  final EdgeInsetsGeometry padding;

  @override
  State<SweepCard> createState() => _SweepCardState();
}

class _SweepCardState extends State<SweepCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SweepCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final turn = GotitMotion.of(context).sweep;
    if (widget.live && turn > Duration.zero) {
      if (_sweep.duration != turn) _sweep.duration = turn;
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final card = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(GotitRadius.card),
        border: Border.all(color: colors.line),
      ),
      child: widget.child,
    );
    if (!widget.live) return card;
    return CustomPaint(
      foregroundPainter: _SweepPainter(
        turn: _sweep,
        accent: colors.accent,
        accent2: colors.accent2,
      ),
      child: card,
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.turn,
    required this.accent,
    required this.accent2,
  }) : super(repaint: turn);

  final Animation<double> turn;
  final Color accent;
  final Color accent2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      const Radius.circular(GotitRadius.card),
    );
    final clear = accent.withValues(alpha: 0);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = SweepGradient(
          colors: [clear, clear, accent, accent2, clear],
          stops: const [0, 0.62, 0.8, 0.92, 1],
          transform: GradientRotation(2 * math.pi * turn.value),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.accent != accent || old.accent2 != accent2;
}
