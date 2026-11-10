import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';

enum StatusTone { ok, waiting, off, warn }

/// A short status with a dot, or a small spinner while [StatusTone.waiting].
class StatusLine extends StatelessWidget {
  const StatusLine(this.text, {required this.tone, super.key});

  final String text;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final theme = Theme.of(context);
    final motion = GotitMotion.of(context);
    final mark = switch (tone) {
      StatusTone.waiting => SizedBox.square(
        dimension: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: colors.accent,
          value: motion.ring == Duration.zero ? 0.7 : null,
        ),
      ),
      _ => AnimatedContainer(
        duration: motion.enter,
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: switch (tone) {
            StatusTone.ok => colors.ok,
            StatusTone.warn => theme.colorScheme.error,
            _ => colors.muted,
          },
        ),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 8),
        Flexible(
          child: AnimatedSwitcher(
            duration: motion.enter,
            child: Text(
              text,
              key: ValueKey(text),
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
