import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/code_cells.dart';
import 'package:gotit/app/widgets/device_node.dart';
import 'package:gotit/core/link/pc_link.dart';

/// On the PC: a phone asks to pair. Compare the code, then Accept or Decline.
class PairRequestSheet extends StatelessWidget {
  const PairRequestSheet({required this.request, super.key});

  final PairRequest request;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    return ColoredBox(
      color: colors.bg.withValues(alpha: 0.94),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const DeviceNode(
                        icon: Icons.smartphone_outlined,
                        size: 56,
                        live: true,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${request.phoneName} wants to pair',
                        style: text.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Check that your phone shows this code',
                        style: text.bodyMedium?.copyWith(color: colors.muted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      CodeCells(code: request.code),
                      if (request.replaces != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Replaces ${request.replaces}',
                          style: text.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _TimeLeft(until: request.expiresAt),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: request.decline,
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: request.accept,
                              child: const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin bar that runs down until the request expires.
class _TimeLeft extends StatelessWidget {
  const _TimeLeft({required this.until});

  final DateTime until;

  @override
  Widget build(BuildContext context) {
    final left = until.difference(DateTime.now());
    final reduced = GotitMotion.reduced(context);
    const full = Duration(seconds: 60);
    final start = (left.inMilliseconds / full.inMilliseconds).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: start, end: reduced ? start : 0),
        duration: left.isNegative ? Duration.zero : left,
        builder: (context, value, _) =>
            LinearProgressIndicator(value: value, minHeight: 3),
      ),
    );
  }
}
