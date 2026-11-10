import 'package:flutter/material.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/catch_mark.dart';
import 'package:gotit/core/update/updater.dart';
import 'package:gotit/features/settings/view/settings_page.dart';

/// Stand-in home screen: the name, the version and updates, until M2's real screens.
class HomePage extends StatelessWidget {
  const HomePage({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    final updater = services.updater;
    return Scaffold(
      appBar: services.isPc
          ? AppBar(
              actions: [
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(services: services),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CatchMark(size: 76, play: true),
                const SizedBox(height: 22),
                Text('Gotit', style: text.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  'Version ${services.version}',
                  style: text.bodyMedium?.copyWith(color: colors.muted),
                ),
                const SizedBox(height: 28),
                ValueListenableBuilder<UpdateState>(
                  valueListenable: updater,
                  builder: (context, state, _) => AnimatedSwitcher(
                    duration: motion.enter,
                    reverseDuration: motion.exit,
                    switchInCurve: GotitMotion.arrive,
                    switchOutCurve: GotitMotion.leave,
                    child: KeyedSubtree(
                      key: ValueKey(state.runtimeType),
                      child: _UpdateLine(state: state, updater: updater),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.state, required this.updater});

  final UpdateState state;
  final Updater updater;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget line(String label) => Text(label, style: style);
    return switch (state) {
      UpdateIdle() || UpdateChecking() => line('Checking for updates'),
      UpdateLocalBuild() => line('Development build'),
      UpdateUpToDate(:final justUpdated) => line(
        justUpdated ? 'Updated' : 'Up to date',
      ),
      UpdateAvailable(:final version) => _WithButton(
        label: 'Version $version is ready',
        button: 'Update',
        onPressed: updater.install,
      ),
      UpdateDownloading(:final version, :final progress) => Column(
        children: [
          line('Downloading $version'),
          const SizedBox(height: 8),
          SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: progress,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
      UpdateInstalling(:final version) => line('Installing $version'),
      UpdateNeedsPermission() => _WithButton(
        label: 'Allow installs from Gotit, then tap Update',
        button: 'Update',
        onPressed: updater.install,
      ),
      UpdateFailed(:final reason) => _WithButton(
        label: reason,
        button: 'Try again',
        onPressed: updater.check,
      ),
    };
  }
}

class _WithButton extends StatelessWidget {
  const _WithButton({
    required this.label,
    required this.button,
    required this.onPressed,
  });

  final String label;
  final String button;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        FilledButton(onPressed: onPressed, child: Text(button)),
      ],
    );
  }
}
