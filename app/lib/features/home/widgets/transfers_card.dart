import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/widgets/sweep_card.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// Files on their way, either way, on home: each with its progress and
/// Cancel, then how it ended, for a little while. Hidden when there are none.
class TransfersCard extends StatelessWidget {
  const TransfersCard({required this.transfers, this.onOpen, super.key});

  final Transfers transfers;

  /// Opens a received file.
  final void Function(String location)? onOpen;

  @override
  Widget build(BuildContext context) {
    final motion = GotitMotion.of(context);
    return ValueListenableBuilder<List<Transfer>>(
      valueListenable: transfers,
      builder: (context, list, _) => AnimatedSize(
        duration: motion.enter,
        curve: GotitMotion.arrive,
        alignment: Alignment.topCenter,
        child: list.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SweepCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Column(
                    children: [
                      for (final transfer in list.reversed)
                        _TransferRow(
                          transfer: transfer,
                          onCancel: () => transfers.cancel(transfer.id),
                          onOpen: onOpen,
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.transfer,
    required this.onCancel,
    required this.onOpen,
  });

  final Transfer transfer;
  final VoidCallback onCancel;
  final void Function(String location)? onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    final sending = transfer.direction == TransferDirection.sending;
    final location = transfer.location;
    final status = switch (transfer.status) {
      TransferStatus.running => null,
      TransferStatus.done => sending ? 'Sent' : 'Received',
      TransferStatus.failed => sending ? "Didn't send" : "Didn't arrive",
      TransferStatus.cancelled => 'Cancelled',
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          Icon(
            sending ? Icons.north_east_rounded : Icons.south_west_rounded,
            size: 18,
            color: transfer.status == TransferStatus.done
                ? colors.accent
                : colors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  transfer.name,
                  style: text.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (transfer.preparing && transfer.running)
                  Text(
                    'Zipping',
                    style: text.bodySmall?.copyWith(color: colors.muted),
                  )
                else if (status == null)
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: transfer.progress ?? 0),
                    duration: motion.tick,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: transfer.progress == null ? null : value,
                        minHeight: 4,
                      ),
                    ),
                  )
                else
                  Text(
                    status,
                    style: text.bodySmall?.copyWith(color: colors.muted),
                  ),
              ],
            ),
          ),
          if (transfer.running)
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onCancel,
            )
          else if (transfer.status == TransferStatus.done &&
              !sending &&
              location != null &&
              onOpen != null)
            TextButton(
              onPressed: () => onOpen!(location),
              child: const Text('Open'),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
