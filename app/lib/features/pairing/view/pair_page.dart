import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/catch_mark.dart';
import 'package:gotit/app/widgets/device_node.dart';
import 'package:gotit/app/widgets/status_line.dart';
import 'package:gotit/core/link/discovery.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/features/pairing/cubit/pairing_cubits.dart';
import 'package:gotit/features/pairing/view/pair_code_page.dart';
import 'package:gotit/features/pairing/view/scan_page.dart';

/// The phone before pairing: the PCs on this Wi-Fi, and Scan QR code.
class PairPage extends StatelessWidget {
  const PairPage({required this.services, super.key});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NearbyCubit(services.finder!),
      child: _PairView(services: services),
    );
  }
}

class _PairView extends StatelessWidget {
  const _PairView({required this.services});

  final AppServices services;

  void _pair(BuildContext context, FoundPc pc) {
    final attempt = services.phoneLink!.pair(pc.endpoints);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PairCodePage(attempt: attempt, pcName: pc.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CatchMark(size: 28),
                  const SizedBox(width: 10),
                  Text('Gotit', style: text.titleMedium),
                ],
              ),
              const SizedBox(height: 32),
              Text('Pair with your PC', style: text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Open Gotit on your PC, on the same Wi-Fi.',
                style: text.bodyMedium?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: BlocBuilder<NearbyCubit, List<FoundPc>>(
                  builder: (context, pcs) => AnimatedSwitcher(
                    duration: motion.enter,
                    switchInCurve: GotitMotion.arrive,
                    child: pcs.isEmpty
                        ? const Align(
                            key: ValueKey('looking'),
                            alignment: Alignment.topLeft,
                            child: StatusLine(
                              'Looking for PCs',
                              tone: StatusTone.waiting,
                            ),
                          )
                        : ListView.separated(
                            key: const ValueKey('list'),
                            itemCount: pcs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) => _PcTile(
                              pc: pcs[i],
                              onTap: () => _pair(context, pcs[i]),
                            ),
                          ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text('Scan QR code'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ScanPage(services: services),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PcTile extends StatelessWidget {
  const _PcTile({required this.pc, required this.onTap});

  final FoundPc pc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final outdated = pc.version != LinkSpec.version;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const DeviceNode(icon: Icons.desktop_windows_outlined, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pc.name, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      outdated ? 'Needs an update' : 'Tap to pair',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
