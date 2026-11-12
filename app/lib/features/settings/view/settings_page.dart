import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/state/settings.dart';

/// Settings: the paired device and Forget on both; on the PC also its name
/// and starting with Windows; on the phone screenshots to the PC and the
/// quick settings tile.
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<Settings>(
        valueListenable: services.settings,
        builder: (context, settings, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (settings.peer case final peer?) ...[
              _Section(services.isPc ? 'Paired phone' : 'Paired PC'),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  title: Text(peer.name),
                  trailing: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => _forget(context, peer.name),
                    child: const Text('Forget'),
                  ),
                ),
              ),
            ],
            if (services.phoneSetup case final setup?)
              _PhoneSettings(
                setup: setup,
                services: services,
                settings: settings,
              ),
            if (services.isPc) ...[
              const _Section('This PC'),
              Card(
                child: Column(
                  children: [
                    _NameField(services: services),
                    const Divider(indent: 16, endIndent: 16),
                    _StartWithWindows(services: services, settings: settings),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: Text('Version ${services.version}', style: text.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

extension on SettingsPage {
  /// Asks first, then unpairs both devices (the other one is told when it is
  /// connected) and goes back home.
  Future<void> _forget(BuildContext context, String name) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget $name?'),
        content: const Text('To share again, pair the two again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await services.pcLink?.forget();
    await services.phoneLink?.forget();
    navigator.popUntil((route) => route.isFirst);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

/// The PC's name, saved when you press Enter or leave the field. Clearing it
/// goes back to the Windows name.
class _NameField extends StatefulWidget {
  const _NameField({required this.services});

  final AppServices services;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.services.pcName,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  void _save() {
    final services = widget.services;
    final typed = _text.text.trim();
    final chosen = typed.isEmpty || typed == services.windowsName
        ? null
        : typed;
    if (chosen != services.settings.value.pcName) {
      unawaited(
        services.settings.save(
          services.settings.value.copyWith(pcName: () => chosen),
        ),
      );
    }
    if (typed.isEmpty) _text.text = services.windowsName;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _focus.unfocus(),
        decoration: InputDecoration(
          labelText: 'Name',
          helperText: 'What your phone calls this PC',
          counterText: '',
          filled: true,
          fillColor: colors.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _StartWithWindows extends StatelessWidget {
  const _StartWithWindows({required this.services, required this.settings});

  final AppServices services;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final startup = services.startup;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: const Text('Start with Windows'),
      subtitle: Text(
        startup == null ? 'Installed copies only' : 'Opens in the tray',
      ),
      value: startup != null && (settings.startWithWindows ?? true),
      onChanged: startup == null
          ? null
          : (on) {
              on ? startup.turnOn() : startup.turnOff();
              unawaited(
                services.settings.save(
                  settings.copyWith(startWithWindows: () => on),
                ),
              );
            },
    );
  }
}

/// The phone's own settings: new screenshots to the PC, and the quick
/// settings tile where Android can offer to add it (Android 13 and later).
class _PhoneSettings extends StatelessWidget {
  const _PhoneSettings({
    required this.setup,
    required this.services,
    required this.settings,
  });

  final PhoneSetup setup;
  final AppServices services;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Section('This phone'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                title: const Text('Screenshots to PC'),
                value: settings.sendsScreenshots,
                onChanged: (on) => unawaited(
                  services.settings.save(
                    services.settings.value.copyWith(screenshots: () => on),
                  ),
                ),
              ),
              FutureBuilder<SetupStatus>(
                future: setup.status(),
                builder: (context, status) {
                  if (status.data?.tileSupported != true) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: [
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                        title: const Text('Quick settings tile'),
                        trailing: TextButton(
                          onPressed: () => unawaited(setup.addTile()),
                          child: const Text('Add'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
