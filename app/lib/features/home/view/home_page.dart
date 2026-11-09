import 'package:flutter/material.dart';
import 'package:gotit/core/update/updater.dart';

/// Stand-in home screen: the name, the version and updates, until M2's real screens.
class HomePage extends StatelessWidget {
  const HomePage({required this.version, required this.updater, super.key});

  final String version;
  final Updater updater;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Gotit', style: text.headlineLarge),
              const SizedBox(height: 8),
              Text('Version $version', style: text.bodyMedium),
              const SizedBox(height: 24),
              ValueListenableBuilder<UpdateState>(
                valueListenable: updater,
                builder: (context, state, _) =>
                    _UpdateLine(state: state, updater: updater),
              ),
            ],
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
          SizedBox(width: 160, child: LinearProgressIndicator(value: progress)),
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
