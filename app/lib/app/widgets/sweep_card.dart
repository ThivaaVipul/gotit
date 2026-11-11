import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';

/// A card whose border carries a glint of light while [live]: the connected
/// look. The glint makes one slow turn when the card goes live and when the
/// app comes back to the front, then rests, so an open window costs nothing
/// while it sits there.
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
  late final AppLifecycleListener _lifecycle;
  bool _wasLive = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _play);
  }

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
    if (widget.live && !_wasLive) _play();
    if (!widget.live) _sweep.stop();
    _wasLive = widget.live;
  }

  /// One turn, ending where it began.
  void _play() {
    final turn = GotitMotion.of(context).sweep;
    if (!widget.live || turn <= Duration.zero) return;
    _sweep.duration = turn;
    unawaited(_sweep.forward(from: 0));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
    // While the glint turns, only the border redraws, not the card's
    // contents or the page around it.
    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _SweepPainter(
          turn: _sweep,
          accent: colors.accent,
          accent2: colors.accent2,
        ),
        child: RepaintBoundary(child: card),
      ),
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
