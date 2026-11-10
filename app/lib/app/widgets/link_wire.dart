import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';

/// The line between two devices: lit while they are linked, faint when not.
class LinkWire extends StatelessWidget {
  const LinkWire({required this.active, super.key});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    return AnimatedContainer(
      duration: GotitMotion.of(context).enter,
      curve: GotitMotion.arrive,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        gradient: active
            ? LinearGradient(
                colors: [
                  Color.lerp(colors.line, colors.accent, 0.5)!,
                  Color.lerp(colors.line, colors.accent2, 0.5)!,
                ],
              )
            : LinearGradient(colors: [colors.line, colors.line]),
      ),
    );
  }
}
