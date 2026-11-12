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
    this.hint,
    this.secondary,
    this.onSecondary,
  });

  final String label;
  final bool done;

  /// The button's word: Allow, Open, Done.
  final String action;
  final VoidCallback onTap;

  /// A short line under the label, for a step that needs one.
  final String? hint;

  /// A second, quieter button before the main one.
  final String? secondary;
  final VoidCallback? onSecondary;
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

  /// The copy watcher: off, on, or stopped or turned off after MIUI killed
  /// the app. Android 13 may grey out its switch for apps from outside a
  /// store until restricted settings are allowed in the app's info page, so
  /// while it is switched off, App info is one tap away.
  static SetupStep _watcherStep(SetupStatus status, SetupCubit cubit) {
    final appInfo =
        status.restricted &&
        (status.watcher == WatcherState.off ||
            status.watcher == WatcherState.turnedOff);
    return SetupStep(
      label: 'Copy watching',
      done: status.watcher == WatcherState.on,
      hint: switch (status.watcher) {
        WatcherState.stopped => 'Stopped. Switch it off and on again',
        WatcherState.turnedOff => 'Turned off. Switch it on again',
        WatcherState.off when status.restricted =>
          'Greyed out? Allow restricted settings in App info',
        _ => null,
      },
      action: 'Open',
      onTap: () => unawaited(cubit.openWatcher()),
      secondary: appInfo ? 'App info' : null,
      onSecondary: () => unawaited(cubit.openAppInfo()),
    );
  }

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
                _watcherStep(status, cubit),
                if (status.xiaomi) ...[
                  SetupStep(
                    label: 'Autostart',
                    done: status.autostart,
                    action: status.autostartOpened ? 'Done' : 'Open',
                    onTap: () => unawaited(
                      status.autostartOpened
                          ? cubit.mark('autostart')
                          : cubit.openAutostart(),
                    ),
                    secondary: status.autostartOpened ? 'Open' : null,
                    onSecondary: () => unawaited(cubit.openAutostart()),
                  ),
                  SetupStep(
                    label: 'Lock in recents',
                    hint: 'Recents: hold Gotit, tap the lock',
                    done: status.locked,
                    action: 'Done',
                    onTap: () => unawaited(cubit.mark('locked')),
                  ),
                ],
                if (status.screenshots)
                  SetupStep(
                    label: 'Screenshots to PC',
                    done: status.photos,
                    action: 'Allow',
                    onTap: () => unawaited(cubit.askPhotos()),
                  ),
                if (status.tileSupported)
                  SetupStep(
                    label: 'Quick settings tile',
                    done: status.tile,
                    action: 'Add',
                    onTap: () => unawaited(cubit.addTile()),
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
    final hint = step.done ? null : step.hint;
    final secondary = step.done ? null : step.secondary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
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
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: hint == null ? 0 : 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.label,
                    style: text.bodyLarge?.copyWith(
                      color: step.done ? colors.muted : colors.fg,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint,
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                ],
              ),
            ),
          ),
          if (secondary != null)
            TextButton(
              onPressed: step.onSecondary,
              style: TextButton.styleFrom(foregroundColor: colors.muted),
              child: Text(secondary),
            ),
          if (!step.done)
            TextButton(onPressed: step.onTap, child: Text(step.action)),
        ],
      ),
    );
  }
}
