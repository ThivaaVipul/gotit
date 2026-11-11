import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/features/setup/cubit/setup_cubit.dart';

/// One step of the checklist.
class SetupStep {
  const SetupStep({
    required this.label,
    required this.done,
    required this.action,
    required this.onTap,
  });

  final String label;
  final bool done;

  /// The button's word: Allow, Open.
  final String action;
  final VoidCallback onTap;
}

/// The phone's setup steps, on home until they are all done.
class SetupChecklist extends StatelessWidget {
  const SetupChecklist({required this.setup, super.key});

  final PhoneSetup setup;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SetupCubit(setup),
      child: const _RefreshOnReturn(child: _ChecklistView()),
    );
  }
}

/// Settings pages open over the app; coming back reads the steps again.
class _RefreshOnReturn extends StatefulWidget {
  const _RefreshOnReturn({required this.child});

  final Widget child;

  @override
  State<_RefreshOnReturn> createState() => _RefreshOnReturnState();
}

class _RefreshOnReturnState extends State<_RefreshOnReturn> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<SetupCubit>().recheck(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ChecklistView extends StatelessWidget {
  const _ChecklistView();

  @override
  Widget build(BuildContext context) {
    final motion = GotitMotion.of(context);
    return BlocBuilder<SetupCubit, SetupStatus?>(
      builder: (context, status) {
        final cubit = context.read<SetupCubit>();
        final steps = status == null
            ? const <SetupStep>[]
            : [
                SetupStep(
                  label: 'Notifications',
                  done: status.notifications,
                  action: 'Allow',
                  onTap: () => unawaited(cubit.askNotifications()),
                ),
                SetupStep(
                  label: 'Battery: no limits',
                  done: status.battery,
                  action: 'Open',
                  onTap: () => unawaited(cubit.askBattery()),
                ),
              ];
        final show = steps.any((step) => !step.done);
        return AnimatedSize(
          duration: motion.enter,
          curve: GotitMotion.arrive,
          alignment: Alignment.topCenter,
          child: show ? SetupCard(steps: steps) : const SizedBox.shrink(),
        );
      },
    );
  }
}

/// The checklist card: a count, a progress bar, and the steps.
class SetupCard extends StatelessWidget {
  const SetupCard({required this.steps, super.key});

  final List<SetupStep> steps;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    final done = steps.where((step) => step.done).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Finish setup', style: text.titleMedium),
                    ),
                    Text('$done of ${steps.length}', style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(color: colors.surface2),
                        ),
                        AnimatedFractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          duration: motion.tick,
                          curve: GotitMotion.move,
                          widthFactor: steps.isEmpty ? 0 : done / steps.length,
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: colors.live),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final step in steps) _StepRow(step: step),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final SetupStep step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          AnimatedContainer(
            duration: motion.tick,
            curve: GotitMotion.move,
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: step.done ? colors.accent : null,
              border: Border.all(
                color: step.done ? colors.accent : colors.line,
                width: 1.5,
              ),
            ),
            child: step.done
                ? Icon(Icons.check_rounded, size: 14, color: colors.onAccent)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.label,
              style: text.bodyLarge?.copyWith(
                color: step.done ? colors.muted : colors.fg,
              ),
            ),
          ),
          if (!step.done)
            TextButton(onPressed: step.onTap, child: Text(step.action)),
        ],
      ),
    );
  }
}
