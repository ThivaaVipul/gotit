import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/code_cells.dart';
import 'package:gotit/app/widgets/device_node.dart';
import 'package:gotit/app/widgets/status_line.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/features/pairing/cubit/pairing_cubits.dart';

/// Pairing in progress on the phone: the code to compare, then the outcome.
class PairCodePage extends StatelessWidget {
  const PairCodePage({required this.attempt, required this.pcName, super.key});

  final PairAttempt attempt;
  final String pcName;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PairingCubit(attempt),
      child: _PairCodeView(pcName: pcName),
    );
  }
}

class _PairCodeView extends StatelessWidget {
  const _PairCodeView({required this.pcName});

  final String pcName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    return BlocConsumer<PairingCubit, PairingState>(
      listenWhen: (before, now) => now.step is PairDone,
      listener: (context, state) {
        // Let the lit-up code be seen, then go home.
        final navigator = Navigator.of(context);
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 900),
            () => navigator.popUntil((route) => route.isFirst),
          ),
        );
      },
      builder: (context, state) {
        final step = state.step;
        final name = switch (step) {
          PairShowCode(:final pcName) when pcName.isNotEmpty => pcName,
          PairDone(:final pc) => pc.name,
          _ => pcName,
        };
        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  const DeviceNode(
                    icon: Icons.desktop_windows_outlined,
                    size: 64,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Pair with $name',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: motion.enter,
                    child: Text(
                      _hint(step, name),
                      key: ValueKey(_hint(step, name)),
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (state.code != null)
                    CodeCells(code: state.code!, confirmed: step is PairDone)
                  else if (step is PairDone)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 64,
                      color: colors.ok,
                    ),
                  const SizedBox(height: 24),
                  _Outcome(step: step, name: name),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: switch (step) {
                      PairRefused() || PairFailed() => FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Try again'),
                      ),
                      PairDone() => const SizedBox.shrink(),
                      _ => OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _hint(PairProgress step, String name) => switch (step) {
    PairConnecting() => 'Connecting',
    PairShowCode() => 'Check that $name shows this code',
    PairDone() => 'Paired',
    PairRefused(:final reason) => _refusal(reason, name),
    PairFailed() => "Couldn't reach $name. Same Wi-Fi?",
  };

  static String _refusal(PairRefusal reason, String name) => switch (reason) {
    PairRefusal.declined => 'Declined on $name',
    PairRefusal.timeout => 'No answer from $name',
    PairRefusal.expired => 'This code has expired. Show a new one on $name.',
    PairRefusal.busy => '$name is pairing another phone',
    PairRefusal.version => 'Update Gotit on both devices',
    PairRefusal.failed => "Couldn't pair",
  };
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.step, required this.name});

  final PairProgress step;
  final String name;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: GotitMotion.of(context).enter,
      child: switch (step) {
        PairConnecting() => const StatusLine(
          'Connecting',
          key: ValueKey('connecting'),
          tone: StatusTone.waiting,
        ),
        PairShowCode() => StatusLine(
          'Waiting for Accept on $name',
          key: const ValueKey('waiting'),
          tone: StatusTone.waiting,
        ),
        PairDone() => const StatusLine(
          'Paired',
          key: ValueKey('paired'),
          tone: StatusTone.ok,
        ),
        _ => const SizedBox.shrink(key: ValueKey('none')),
      },
    );
  }
}
