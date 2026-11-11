import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/device_node.dart';
import 'package:gotit/app/widgets/link_wire.dart';
import 'package:gotit/app/widgets/status_line.dart';
import 'package:gotit/app/widgets/sweep_card.dart';
import 'package:gotit/core/link/pairing.dart';
import 'package:gotit/core/link/pc_link.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/core/platform/device.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/features/home/cubit/link_cubits.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Follows the sharing switch, where there is one.
class _SharingAware extends StatelessWidget {
  const _SharingAware({required this.sharing, required this.builder});

  final ValueListenable<SharingState>? sharing;
  final Widget Function(bool on) builder;

  @override
  Widget build(BuildContext context) {
    final sharing = this.sharing;
    if (sharing == null) return builder(true);
    return ValueListenableBuilder<SharingState>(
      valueListenable: sharing,
      builder: (context, state, _) => builder(state.on),
    );
  }
}

/// The two devices and the link between them, with the other one's name and
/// how the link stands. While sharing is off the link is still up, but the
/// card rests: "Sharing off", the other device dimmed and nothing moving.
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.here,
    required this.there,
    required this.name,
    required this.status,
    required this.tone,
    required this.online,
    this.sharingOn = true,
    super.key,
  });

  final IconData here;
  final IconData there;
  final String name;
  final String status;
  final StatusTone tone;
  final bool online;
  final bool sharingOn;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final live = online && sharingOn;
    final paused = online && !sharingOn;
    return SweepCard(
      live: live,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              DeviceNode(icon: here),
              Expanded(child: LinkWire(active: live)),
              DeviceNode(icon: there, live: live, muted: !live),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            name,
            style: text.headlineSmall,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          StatusLine(
            paused ? 'Sharing off' : status,
            tone: paused ? StatusTone.off : tone,
          ),
        ],
      ),
    );
  }
}

/// The phone's home: the paired PC and the link.
class PhoneLinkHero extends StatelessWidget {
  const PhoneLinkHero({this.sharing, super.key});

  final ValueListenable<SharingState>? sharing;

  @override
  Widget build(BuildContext context) => _SharingAware(
    sharing: sharing,
    builder: (sharingOn) => _build(context, sharingOn),
  );

  Widget _build(BuildContext context, bool sharingOn) {
    return BlocBuilder<PhoneLinkCubit, PhoneLinkState>(
      builder: (context, state) {
        final pc = state.pc;
        if (pc == null) return const SizedBox.shrink();
        final (status, tone) = switch (state.connection) {
          Connection.online => ('Connected', StatusTone.ok),
          Connection.mismatch => (
            (state.theirVersion ?? 0) > LinkSpec.version
                ? 'Update Gotit on this phone'
                : 'Update Gotit on ${pc.name}',
            StatusTone.warn,
          ),
          _ => ('Looking for ${pc.name}', StatusTone.waiting),
        };
        return _LinkCard(
          here: Icons.smartphone_outlined,
          there: Icons.desktop_windows_outlined,
          name: pc.name,
          status: status,
          tone: tone,
          online: state.connection == Connection.online,
          sharingOn: sharingOn,
        );
      },
    );
  }
}

/// The PC's home: waiting for a phone, or the paired phone and the link.
class PcLinkHero extends StatelessWidget {
  const PcLinkHero({required this.link, this.sharing, super.key});

  final PcLink link;
  final ValueListenable<SharingState>? sharing;

  @override
  Widget build(BuildContext context) => _SharingAware(
    sharing: sharing,
    builder: (sharingOn) => _build(context, sharingOn),
  );

  Widget _build(BuildContext context, bool sharingOn) {
    return BlocBuilder<PcLinkCubit, PcLinkState>(
      builder: (context, state) {
        final phone = state.phone;
        return AnimatedSwitcher(
          duration: GotitMotion.of(context).enter,
          switchInCurve: GotitMotion.arrive,
          switchOutCurve: GotitMotion.leave,
          child: phone == null
              ? _Waiting(key: const ValueKey('waiting'), link: link)
              : _LinkCard(
                  key: const ValueKey('paired'),
                  here: Icons.desktop_windows_outlined,
                  there: Icons.smartphone_outlined,
                  name: phone.name,
                  status: switch (state.connection) {
                    Connection.online => 'Connected',
                    Connection.mismatch =>
                      (state.theirVersion ?? 0) > LinkSpec.version
                          ? 'Update Gotit on this PC'
                          : 'Update Gotit on ${phone.name}',
                    _ => 'Not connected',
                  },
                  tone: switch (state.connection) {
                    Connection.online => StatusTone.ok,
                    Connection.mismatch => StatusTone.warn,
                    _ => StatusTone.off,
                  },
                  online: state.connection == Connection.online,
                  sharingOn: sharingOn,
                ),
        );
      },
    );
  }
}

/// No phone yet: how to pair, and the QR code for when the phone can't see
/// the PC on the network.
class _Waiting extends StatefulWidget {
  const _Waiting({required this.link, super.key});

  final PcLink link;

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  PairInvite? _invite;
  Timer? _refresh;

  Future<void> _showCode() async {
    final hosts = await localAddresses();
    if (!mounted) return;
    setState(() => _invite = widget.link.invite(hosts));
    // A fresh code before the old one runs out.
    _refresh?.cancel();
    _refresh = Timer.periodic(
      LinkSpec.inviteLifetime - const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() => _invite = widget.link.invite(hosts));
      },
    );
  }

  void _hideCode() {
    _refresh?.cancel();
    setState(() => _invite = null);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final invite = _invite;
    return SweepCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        children: [
          const DeviceNode(icon: Icons.smartphone_outlined, muted: true),
          const SizedBox(height: 16),
          Text('Waiting for your phone', style: text.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Open Gotit on your phone, on the same Wi-Fi.',
            style: text.bodyMedium?.copyWith(color: colors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: GotitMotion.of(context).enter,
            curve: GotitMotion.arrive,
            child: invite == null
                ? TextButton.icon(
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: const Text('Show QR code'),
                    onPressed: _showCode,
                  )
                : Column(
                    children: [
                      const SizedBox(height: 6),
                      _Qr(data: invite.encode()),
                      const SizedBox(height: 12),
                      Text(
                        'Scan with Gotit on your phone',
                        style: text.bodySmall,
                      ),
                      TextButton(
                        onPressed: _hideCode,
                        child: const Text('Hide'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Qr extends StatelessWidget {
  const _Qr({required this.data});

  final String data;

  // QR codes scan best dark on white, whatever the theme.
  static const _ink = Color(0xFF0B0C10);
  static const _paper = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR code for pairing',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(12),
        ),
        child: QrImageView(
          data: data,
          size: 188,
          padding: EdgeInsets.zero,
          backgroundColor: _paper,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: _ink,
          ),
        ),
      ),
    );
  }
}
