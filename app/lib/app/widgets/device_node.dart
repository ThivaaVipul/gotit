import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';

/// A device on the link: an icon on a soft accent tile. While [live], a ring
/// pulses out from it every couple of seconds.
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
  late final AnimationController _ring = AnimationController(vsync: this);

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
    final beat = GotitMotion.of(context).ring;
    if (widget.live && beat > Duration.zero) {
      if (_ring.duration != beat) _ring.duration = beat;
      if (!_ring.isAnimating) _ring.repeat();
    } else {
      _ring
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
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
              child: AnimatedBuilder(
                animation: _ring,
                builder: (context, _) {
                  final t = Curves.decelerate.transform(_ring.value);
                  return Opacity(
                    opacity: (1 - t) * 0.55,
                    child: Transform.scale(
                      scale: 1 + 0.45 * t,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(color: colors.accent, width: 2),
                        ),
                      ),
                    ),
                  );
                },
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
