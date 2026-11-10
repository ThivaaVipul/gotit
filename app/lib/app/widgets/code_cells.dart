import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';

/// The pairing code, one digit per cell. The digits sharpen into focus one
/// after another; once [confirmed], the cells light up.
class CodeCells extends StatefulWidget {
  const CodeCells({required this.code, this.confirmed = false, super.key});

  final String code;
  final bool confirmed;

  @override
  State<CodeCells> createState() => _CodeCellsState();
}

class _CodeCellsState extends State<CodeCells>
    with SingleTickerProviderStateMixin {
  static const _digitTime = Duration(milliseconds: 500);
  late final AnimationController _reveal = AnimationController(vsync: this);
  Duration _stagger = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = GotitMotion.of(context);
    _stagger = motion.stagger;
    final total =
        motion.stagger * 3 +
        (motion.enter > Duration.zero ? _digitTime : Duration.zero);
    if (total == Duration.zero) {
      _reveal.value = 1;
    } else if (_reveal.value == 0 && !_reveal.isAnimating) {
      _reveal
        ..duration = total
        ..forward();
    }
  }

  @override
  void didUpdateWidget(CodeCells old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code && _reveal.duration != null) {
      _reveal.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// How far digit [i] is into focus, 0 to 1.
  double _focus(int i) {
    final total = _reveal.duration?.inMicroseconds ?? 0;
    if (total == 0) return 1;
    final start = (_stagger * i).inMicroseconds / total;
    final end = start + _digitTime.inMicroseconds / total;
    final t = ((_reveal.value - start) / (end - start)).clamp(0.0, 1.0);
    return GotitMotion.arrive.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    final digits = widget.code.split('');
    return Semantics(
      label: 'Code ${digits.join(' ')}',
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < digits.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              TweenAnimationBuilder<double>(
                key: ValueKey((i, widget.confirmed)),
                tween: Tween(begin: widget.confirmed ? 1.08 : 1, end: 1),
                duration: motion.toggle,
                curve: GotitMotion.spring,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: AnimatedContainer(
                  duration: motion.toggle,
                  curve: GotitMotion.arrive,
                  width: 60,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.confirmed ? colors.accent : colors.surface,
                    borderRadius: BorderRadius.circular(GotitRadius.control),
                    border: Border.all(
                      color: widget.confirmed ? colors.accent : colors.line,
                    ),
                  ),
                  child: _Digit(
                    digit: digits[i],
                    focus: _focus(i),
                    color: widget.confirmed ? colors.onAccent : colors.fg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Digit extends StatelessWidget {
  const _Digit({required this.digit, required this.focus, required this.color});

  final String digit;
  final double focus;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      digit,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final blur = 8 * (1 - focus);
    return Opacity(
      opacity: focus,
      child: Transform.scale(
        scale: 1.15 - 0.15 * focus,
        child: blur < 0.05
            ? text
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: text,
              ),
      ),
    );
  }
}
