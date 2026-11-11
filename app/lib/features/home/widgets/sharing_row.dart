import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/sweep_card.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/state/settings.dart';

/// The sharing switch on home, under the link: on for both devices, or
/// paused on both. Shown once paired.
class SharingRow extends StatelessWidget {
  const SharingRow({required this.sharing, required this.settings, super.key});

  final SharingSwitch sharing;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    return ValueListenableBuilder<Settings>(
      valueListenable: settings,
      builder: (context, saved, _) {
        if (saved.peer == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ValueListenableBuilder<SharingState>(
            valueListenable: sharing,
            builder: (context, state, _) => MergeSemantics(
              child: SweepCard(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sharing', style: text.titleMedium),
                          const SizedBox(height: 2),
                          AnimatedSwitcher(
                            duration: motion.enter,
                            switchInCurve: GotitMotion.arrive,
                            switchOutCurve: GotitMotion.leave,
                            child: Text(
                              state.on
                                  ? 'Copies cross both ways'
                                  : 'Paused on both devices',
                              key: ValueKey(state.on),
                              style: text.bodySmall?.copyWith(
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: state.on,
                      onChanged: (on) => sharing.set(on: on),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
