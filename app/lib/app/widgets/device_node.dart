import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';

/// A device on the link: an icon on a soft accent tile. When it goes [live],
/// and when the app comes back to the front, a ring pulses out from it a few
/// times, then rests, so an open window costs nothing while it sits there.
class DeviceNode extends StatefulWidget {
  const DeviceNode({
    required this.icon,
    this.size = 54,
    this.live = false,
    this.muted = false,
    super.key,
  });

  final IconData icon;
  final double size;
  final bool live;

  /// Greyed out: the device isn't reachable.
  final bool muted;

  @override
  State<DeviceNode> createState() => _DeviceNodeState();
}

class _DeviceNodeState extends State<DeviceNode>
    with SingleTickerProviderStateMixin {
  /// Pulses each time the ring plays.
  static const _beats = 3;

  late final AnimationController _ring = AnimationController(vsync: this);
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
  void didUpdateWidget(DeviceNode old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.live && !_wasLive) _play();
    if (!widget.live) _ring.stop();
    _wasLive = widget.live;
  }

  void _play() {
    final beat = GotitMotion.of(context).ring;
    if (!widget.live || beat <= Duration.zero) return;
    _ring.duration = beat;
    unawaited(_ring.repeat(count: _beats));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final radius = BorderRadius.circular(widget.size * 0.2);
    final tint = widget.muted ? colors.muted : colors.accent;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.live)
            Positioned.fill(
              // Only the ring redraws while it pulses.
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _ring,
                  builder: (context, _) {
                    // Drawn only while it plays.
                    if (!_ring.isAnimating) return const SizedBox.shrink();
                    final t = Curves.decelerate.transform(_ring.value);
                    return Transform.scale(
                      scale: 1 + 0.45 * t,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: colors.accent.withValues(
                              alpha: (1 - t) * 0.55,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: GotitMotion.of(context).enter,
              decoration: BoxDecoration(
                color: widget.muted ? colors.surface2 : colors.soft,
                borderRadius: radius,
              ),
              child: Icon(widget.icon, color: tint, size: widget.size * 0.44),
            ),
          ),
        ],
      ),
    );
  }
}
