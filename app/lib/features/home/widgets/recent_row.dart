import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/recent/recent.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// A row of the recent list: an item that crossed, or a file on its way.
sealed class RecentEntry {
  const RecentEntry();

  /// Stays the same while the row stays where it is. An item copied again
  /// gets a new one, so it leaves its place and arrives at the top.
  String get key;
}

class ItemEntry extends RecentEntry {
  const ItemEntry(this.item);

  final RecentItem item;

  @override
  String get key => 'r:${item.id}:${item.at.microsecondsSinceEpoch}';
}

class TransferEntry extends RecentEntry {
  const TransferEntry(this.transfer);

  final Transfer transfer;

  @override
  String get key => 't:${transfer.id}';
}

/// When [at] was, as the list says it: "now", "5 min", "3 h", "Yesterday",
/// a weekday, or a date.
String recentAgo(DateTime at, DateTime now) {
  final gone = now.difference(at);
  if (gone.inSeconds < 45) return 'now';
  if (gone.inMinutes < 60) return '${math.max(1, gone.inMinutes)} min';
  if (gone.inHours < 24) return '${gone.inHours} h';
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 1) return 'Yesterday';
  if (days < 7) return _weekdays[at.weekday - 1];
  return '${at.day} ${_months[at.month - 1]}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// [bytes] for people: "512 B", "18 KB", "2.4 MB", "1.2 GB". Empty when
/// unknown.
String fileSize(int bytes) {
  if (bytes < 0) return '';
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB';
}

/// A file's type as a short label ("PDF"), or null when it has none.
String? fileBadge(String name) {
  final type = extensionOf(name).toUpperCase();
  return type.isEmpty || type.length > 4 ? null : type;
}

/// What a sensitive item shows instead of itself.
const hiddenText = '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';

/// One row: an icon or thumbnail, the name, then which way it went, when,
/// and how big; a [trailing] button. [copied] says so for a moment after a
/// tap put it back on the clipboard.
class RecentRow extends StatelessWidget {
  const RecentRow({
    required this.entry,
    required this.now,
    this.copied = false,
    this.divider = false,
    this.trailing,
    this.onTap,
    this.onMenu,
    super.key,
  });

  final RecentEntry entry;
  final DateTime now;
  final bool copied;

  /// A hairline above it: every row but the first.
  final bool divider;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Its menu: a long press, or a right-click at a position.
  final void Function(Offset? at)? onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    final menu = onMenu;
    return Stack(
      children: [
        AnimatedContainer(
          duration: copied ? Duration.zero : motion.enter * 2,
          curve: GotitMotion.arrive,
          color: copied ? colors.soft : colors.soft.withValues(alpha: 0),
          child: InkWell(
            onTap: onTap,
            onLongPress: menu == null ? null : () => menu(null),
            onSecondaryTapUp: menu == null
                ? null
                : (details) => menu(details.globalPosition),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Row(
                  children: [
                    _Lead(entry: entry),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Title(entry: entry),
                          const SizedBox(height: 2),
                          _Second(entry: entry, now: now, copied: copied),
                        ],
                      ),
                    ),
                    trailing ?? const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (divider)
          Positioned(
            top: 0,
            left: 60,
            right: 0,
            child: IgnorePointer(
              child: Container(height: 1, color: colors.line),
            ),
          ),
      ],
    );
  }
}

class _Lead extends StatelessWidget {
  const _Lead({required this.entry});

  final RecentEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget tile(Widget child, {bool accent = false}) => Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent ? colors.soft : colors.surface2,
        borderRadius: BorderRadius.circular(GotitRadius.control),
      ),
      child: child,
    );
    Widget icon(IconData data, {bool accent = false}) => tile(
      Icon(data, size: 20, color: accent ? colors.accent : colors.muted),
      accent: accent,
    );
    Widget badge(String name, IconData fallback) {
      final label = fileBadge(name);
      if (label == null) return icon(fallback);
      return tile(
        Text(
          label,
          style: text.labelSmall?.copyWith(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: colors.muted,
          ),
        ),
      );
    }

    switch (entry) {
      case TransferEntry(:final transfer):
        return badge(transfer.name, Icons.insert_drive_file_outlined);
      case ItemEntry(:final item):
        if (item.sensitive) return icon(Icons.lock_outline_rounded);
        switch (item.kind) {
          case RecentKind.text:
            return icon(Icons.notes_rounded);
          case RecentKind.link:
            return icon(Icons.link_rounded, accent: true);
          case RecentKind.image:
            final path = item.image;
            if (path == null) return icon(Icons.image_outlined);
            final pixels = (36 * MediaQuery.devicePixelRatioOf(context))
                .round();
            return ClipRRect(
              borderRadius: BorderRadius.circular(GotitRadius.control),
              child: Image.file(
                File(path),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                cacheWidth: pixels,
                gaplessPlayback: true,
                errorBuilder: (context, _, _) => icon(Icons.image_outlined),
              ),
            );
          case RecentKind.files:
            if (item.files.length == 1) {
              return badge(
                item.files.single.name,
                Icons.insert_drive_file_outlined,
              );
            }
            final images = item.files.every((file) => isImageName(file.name));
            return icon(
              images
                  ? Icons.photo_library_outlined
                  : Icons.folder_copy_outlined,
            );
        }
    }
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.entry});

  final RecentEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final style = Theme.of(context).textTheme.bodyMedium;
    final muted = style?.copyWith(color: colors.muted);
    Widget line(String text, {TextStyle? textStyle}) => Text(
      text,
      style: textStyle ?? style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    Widget two(String first, String rest) => Text.rich(
      TextSpan(
        text: first,
        children: [TextSpan(text: rest, style: muted)],
      ),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    switch (entry) {
      case TransferEntry(:final transfer):
        return line(transfer.name);
      case ItemEntry(:final item):
        if (item.sensitive) {
          return line(
            hiddenText,
            textStyle: style?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          );
        }
        switch (item.kind) {
          case RecentKind.text:
            final first = item.text
                .split('\n')
                .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
                .trim();
            return line(first);
          case RecentKind.link:
            final shown = shownLink(item.text);
            final slash = shown.indexOf('/');
            return slash < 0
                ? line(shown)
                : two(shown.substring(0, slash), shown.substring(slash));
          case RecentKind.image:
            return line(item.screenshot ? 'Screenshot' : 'Image');
          case RecentKind.files:
            final first = item.files.first.name;
            final more = item.files.length - 1;
            return more == 0 ? line(first) : two(first, ' and $more more');
        }
    }
  }
}

class _Second extends StatelessWidget {
  const _Second({required this.entry, required this.now, required this.copied});

  final RecentEntry entry;
  final DateTime now;
  final bool copied;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final motion = GotitMotion.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.muted);
    switch (entry) {
      case TransferEntry(:final transfer):
        final sending = transfer.direction == TransferDirection.sending;
        if (transfer.running) {
          if (transfer.preparing) return Text('Zipping', style: style);
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2, right: 8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: transfer.progress ?? 0),
              duration: motion.tick,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: transfer.progress == null ? null : value,
                  minHeight: 4,
                ),
              ),
            ),
          );
        }
        return Text(switch (transfer.status) {
          TransferStatus.done => sending ? 'Sent' : 'Received',
          TransferStatus.failed => sending ? "Didn't send" : "Didn't arrive",
          _ => 'Cancelled',
        }, style: style);
      case ItemEntry(:final item):
        if (copied) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 14, color: colors.accent),
              const SizedBox(width: 4),
              Text(
                'Copied',
                style: style?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }
        final extras = [
          recentAgo(item.at, now),
          if (item.kind == RecentKind.image && item.width > 0)
            '${item.width} x ${item.height}',
          if (item.kind == RecentKind.files && item.totalSize > 0)
            fileSize(item.totalSize),
        ];
        return Row(
          children: [
            Icon(
              item.way == RecentWay.sent
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              size: 14,
              color: colors.muted,
              semanticLabel: item.way == RecentWay.sent ? 'Sent' : 'Received',
            ),
            const SizedBox(width: 4),
            for (final (index, part) in extras.indexed) ...[
              if (index > 0) _Dot(color: colors.muted),
              Flexible(
                child: Text(
                  part,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
    }
  }
}

/// The small dot between the parts of a row's second line.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 3,
    height: 3,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A ring that empties as a sensitive item's minute runs out.
class Countdown extends StatelessWidget {
  const Countdown({
    required this.deadline,
    required this.length,
    required this.now,
    super.key,
  });

  final DateTime deadline;
  final Duration length;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final left = deadline.difference(now);
    final start = (left.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);
    Widget ring(double value) => CustomPaint(
      size: const Size.square(18),
      painter: _RingPainter(
        value: value,
        track: colors.surface2,
        color: colors.muted,
      ),
    );
    return Semantics(
      label: 'Leaves in ${math.max(0, left.inSeconds)} seconds',
      child: SizedBox.square(
        dimension: 40,
        // Only the ring redraws while it runs down.
        child: RepaintBoundary(
          child: Center(
            child: GotitMotion.reduced(context) || left <= Duration.zero
                ? ring(start)
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: start, end: 0),
                    duration: left,
                    builder: (context, value, _) => ring(value),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.color});

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.color != color;
}
