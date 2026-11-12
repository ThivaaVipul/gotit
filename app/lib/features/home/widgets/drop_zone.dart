import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/platform/pc_files.dart';

/// The PC's drop area on home: "Drop files here to send" in a dashed
/// outline, lit while files hover over the window. The drop itself can land
/// anywhere on the window; the runner hands it over through [PcFiles].
class DropZone extends StatelessWidget {
  const DropZone({required this.files, required this.phone, super.key});

  final PcFiles files;

  /// The paired phone's name.
  final String phone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ValueListenableBuilder<bool>(
        valueListenable: files.dragging,
        builder: (context, hovering, _) => AnimatedContainer(
          duration: motion.tap,
          curve: GotitMotion.arrive,
          decoration: BoxDecoration(
            color: hovering ? colors.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(GotitRadius.card),
          ),
          child: CustomPaint(
            painter: _Outline(
              color: hovering
                  ? colors.accent
                  : colors.muted.withValues(alpha: 0.35),
              dashed: !hovering,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  Text(
                    hovering
                        ? 'Drop to send to $phone'
                        : 'Drop files here to send',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: hovering ? colors.accent : colors.muted,
                    ),
                  ),
                  // The shortcut, or that another app holds it.
                  ValueListenableBuilder<bool?>(
                    valueListenable: files.hotkey,
                    builder: (context, ready, _) => ready == null || hovering
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              ready
                                  ? 'or copy them and press Ctrl+F2'
                                  : 'Ctrl+F2 is taken by another app',
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded outline, dashed while waiting and solid while files hover.
class _Outline extends CustomPainter {
  _Outline({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(GotitRadius.card),
        ).deflate(0.75),
      );
    if (!dashed) {
      canvas.drawPath(outline, paint);
      return;
    }
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 9) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + 5, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Outline old) =>
      old.color != color || old.dashed != dashed;
}
