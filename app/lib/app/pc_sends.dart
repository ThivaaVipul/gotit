import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gotit/app/desktop_shell.dart';
import 'package:gotit/core/platform/pc_notices.dart';
import 'package:gotit/core/transfer/pc_sender.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// Answers the PC's sends where they came from. Files dropped on the window
/// are answered in the window, where their progress shows. Send to and
/// Ctrl+F2 start from the tray, so they are answered with toasts, and the
/// tray's check once the files arrived. Sharing off always asks in the
/// window, which comes forward for it.
class PcSends {
  PcSends({
    required this.sender,
    required this.notices,
    required this.navigator,
    required this.phoneName,
    this.shell,
  });

  final PcSender sender;
  final PcNotices notices;
  final GlobalKey<NavigatorState> navigator;
  final String Function() phoneName;
  final DesktopShell? shell;

  /// Files dropped on the window.
  Future<void> dropped(List<String> paths) async {
    final answer = await sender.send(paths, onDone: _done);
    await _answerInWindow(paths, answer);
  }

  /// Files from Send to, or copied ones for Ctrl+F2 ([hotkey]).
  Future<void> fromTray(List<String> paths, {bool hotkey = false}) async {
    final names = [for (final file in sender.filesAt(paths)) file.name];
    final answer = await sender.send(
      paths,
      onDone: (result) => _done(result, toasts: true),
    );
    final phone = phoneName();
    switch (answer) {
      case SendAnswer.sending:
        await notices.say(
          'Sending to $phone',
          body: names.length == 1 ? names.single : '${names.length} files',
        );
      case SendAnswer.nothing:
        await (hotkey
            ? notices.say(
                'No files copied',
                body: 'Copy files in Explorer, then press Ctrl+F2',
              )
            : notices.say('Nothing to send'));
      case SendAnswer.unpaired:
        await notices.say('Pair Gotit with your phone first');
      case SendAnswer.off:
        await _askToTurnOn(paths);
      case SendAnswer.away:
        await notices.say("$phone isn't connected");
    }
  }

  void _done(SendResult result, {bool toasts = false}) {
    switch (result) {
      case SendResult.sent:
        shell?.flashSent();
      case SendResult.away when toasts:
        unawaited(notices.say("${phoneName()} isn't connected"));
      case SendResult.failed when toasts:
        unawaited(notices.say("Couldn't send to ${phoneName()}"));
      case SendResult.away || SendResult.failed || SendResult.cancelled:
        break;
    }
  }

  Future<void> _answerInWindow(List<String> paths, SendAnswer answer) async {
    switch (answer) {
      case SendAnswer.sending:
        break;
      case SendAnswer.nothing:
        _say('Nothing to send');
      case SendAnswer.unpaired:
        _say('Pair Gotit with your phone first');
      case SendAnswer.off:
        await _askToTurnOn(paths);
      case SendAnswer.away:
        _say("${phoneName()} isn't connected");
    }
  }

  /// Sharing is off for both devices: turn it on and send, or leave it.
  Future<void> _askToTurnOn(List<String> paths) async {
    await shell?.showWindow();
    // Just after a start (Send to), the first screen may not be built yet.
    var context = navigator.currentContext;
    for (var tries = 0; context == null && tries < 30; tries++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      context = navigator.currentContext;
    }
    if (context == null || !context.mounted) return;
    final turnOn = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sharing is off'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn on and send'),
          ),
        ],
      ),
    );
    if (turnOn != true) return;
    final answer = await sender.send(paths, turnOn: true, onDone: _done);
    await _answerInWindow(paths, answer);
  }

  void _say(String message) {
    final context = navigator.currentContext;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}
