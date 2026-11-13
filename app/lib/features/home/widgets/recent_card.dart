import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/app/theme/gotit_motion.dart';
import 'package:gotit/app/theme/gotit_theme.dart';
import 'package:gotit/core/recent/recent.dart';
import 'package:gotit/core/recent/recent_actions.dart';
import 'package:gotit/core/state/settings.dart';
import 'package:gotit/core/transfer/transfers.dart';
import 'package:gotit/features/home/widgets/recent_row.dart';

/// Home's Recent card: files on their way at the top, with progress and
/// Cancel, then the last things that crossed either way. A tap copies text,
/// a link or an image back here, or opens a file; a long press (phone) or a
/// right-click (PC) has the rest, Remove included, and Clear empties it.
/// Removing says so with Undo. Shown once paired, or while it holds items.
class RecentCard extends StatefulWidget {
  const RecentCard({
    required this.list,
    required this.actions,
    required this.isPc,
    required this.settings,
    this.transfers,
    super.key,
  });

  final RecentList list;
  final RecentActions actions;
  final bool isPc;
  final SettingsStore settings;
  final Transfers? transfers;

  @override
  State<RecentCard> createState() => _RecentCardState();
}

enum _Do { copy, openLink, open, openFolder, reveal, share, cancel, remove }

class _RecentCardState extends State<RecentCard> {
  final _listKey = GlobalKey<AnimatedListState>();
  late List<RecentEntry> _shown;
  String? _copied;
  Timer? _copiedTimer;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _shown = _entries();
    widget.list.addListener(_sync);
    widget.transfers?.addListener(_sync);
    widget.settings.addListener(_settingsChanged);
    // "2 min" becomes "3 min".
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(RecentCard old) {
    super.didUpdateWidget(old);
    if (old.list != widget.list) {
      old.list.removeListener(_sync);
      widget.list.addListener(_sync);
    }
    if (old.transfers != widget.transfers) {
      old.transfers?.removeListener(_sync);
      widget.transfers?.addListener(_sync);
    }
    if (old.settings != widget.settings) {
      old.settings.removeListener(_settingsChanged);
      widget.settings.addListener(_settingsChanged);
    }
    if (old.list != widget.list || old.transfers != widget.transfers) _sync();
  }

  @override
  void dispose() {
    widget.list.removeListener(_sync);
    widget.transfers?.removeListener(_sync);
    widget.settings.removeListener(_settingsChanged);
    _copiedTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _settingsChanged() => setState(() {});

  /// Files on their way first, newest batch on top and its files in order,
  /// then the list.
  List<RecentEntry> _entries() {
    final moving = widget.transfers?.value ?? const <Transfer>[];
    final batches = <String, List<Transfer>>{};
    for (final transfer in moving) {
      batches.putIfAbsent(transfer.batch, () => []).add(transfer);
    }
    return [
      for (final batch in batches.values.toList().reversed)
        for (final transfer in batch) TransferEntry(transfer),
      for (final item in widget.list.value) ItemEntry(item),
    ];
  }

  /// Brings the shown rows in line with the list and the transfers: rows
  /// that went leave, new ones arrive, the rest update where they are.
  void _sync() {
    if (!mounted) return;
    final next = _entries();
    final list = _listKey.currentState;
    final motion = GotitMotion.of(context);
    final wanted = {for (final entry in next) entry.key};
    for (var i = _shown.length - 1; i >= 0; i--) {
      if (!wanted.contains(_shown[i].key)) {
        _removeAt(list, i, motion.exit);
      }
    }
    for (var i = 0; i < next.length; i++) {
      final want = next[i];
      if (i < _shown.length && _shown[i].key == want.key) {
        _shown[i] = want;
        continue;
      }
      // Found further down: it moved, so it leaves there and arrives here.
      final later = _shown.indexWhere((e) => e.key == want.key, i + 1);
      if (later >= 0) _removeAt(list, later, Duration.zero);
      _shown.insert(i, want);
      list?.insertItem(i, duration: motion.enter);
    }
    while (_shown.length > next.length) {
      _removeAt(list, _shown.length - 1, motion.exit);
    }
    setState(() {});
  }

  void _removeAt(AnimatedListState? list, int index, Duration duration) {
    final gone = _shown.removeAt(index);
    list?.removeItem(
      index,
      (context, animation) =>
          _appear(animation, _row(gone, index, removing: true)),
      duration: duration,
    );
  }

  Widget _appear(Animation<double> animation, Widget child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: GotitMotion.arrive,
      reverseCurve: GotitMotion.leave,
    );
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: curved, child: child),
    );
  }

  // --------------------------------------------------------------------

  Widget _row(RecentEntry entry, int index, {bool removing = false}) {
    final now = DateTime.now();
    final menu = _menuFor(entry);
    return RecentRow(
      key: ValueKey(entry.key),
      entry: entry,
      now: now,
      divider: index > 0,
      copied: entry is ItemEntry && entry.item.id == _copied,
      trailing: removing ? null : _trailing(entry, now),
      onTap: removing ? null : _tapFor(entry),
      onMenu: removing || menu.isEmpty
          ? null
          : (at) => unawaited(_openMenu(entry, menu, at)),
    );
  }

  VoidCallback? _tapFor(RecentEntry entry) {
    if (entry is! ItemEntry) return null;
    final item = entry.item;
    if (item.copyable) return () => _run(_Do.copy, entry);
    final received = item.way == RecentWay.received;
    if (received) {
      return () =>
          _run(item.files.length == 1 ? _Do.open : _Do.openFolder, entry);
    }
    return widget.isPc ? () => _run(_Do.reveal, entry) : null;
  }

  Widget? _trailing(RecentEntry entry, DateTime now) {
    switch (entry) {
      case TransferEntry(:final transfer):
        if (!transfer.running) return null;
        return IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: () => _run(_Do.cancel, entry),
        );
      case ItemEntry(:final item):
        if (item.sensitive) {
          final deadline = widget.list.deadlineOf(item.id);
          if (deadline == null) return null;
          return Countdown(
            deadline: deadline,
            length: widget.list.sensitiveFor,
            now: now,
          );
        }
        Widget button(IconData icon, String tip, _Do what) => IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 20),
          onPressed: () => _run(what, entry),
        );
        switch (item.kind) {
          case RecentKind.text:
            return null;
          case RecentKind.link:
            return TextButton(
              onPressed: () => _run(_Do.openLink, entry),
              child: const Text('Open'),
            );
          case RecentKind.image:
            return widget.isPc
                ? button(Icons.open_in_new_rounded, 'Open', _Do.open)
                : button(Icons.share_outlined, 'Share', _Do.share);
          case RecentKind.files:
            if (widget.isPc) {
              return button(
                Icons.folder_open_outlined,
                'Show in folder',
                _Do.reveal,
              );
            }
            return item.way == RecentWay.received
                ? button(Icons.share_outlined, 'Share', _Do.share)
                : null;
        }
    }
  }

  /// What the long press or right-click offers.
  List<_Do> _menuFor(RecentEntry entry) {
    switch (entry) {
      case TransferEntry(:final transfer):
        return [if (transfer.running) _Do.cancel];
      case ItemEntry(:final item):
        final pc = widget.isPc;
        final received = item.way == RecentWay.received;
        return [
          if (item.copyable) _Do.copy,
          if (item.kind == RecentKind.link) _Do.openLink,
          if (item.kind == RecentKind.image) pc ? _Do.open : _Do.share,
          if (item.kind == RecentKind.files && received) ...[
            if (item.files.length == 1) _Do.open else _Do.openFolder,
            if (!pc) _Do.share,
          ],
          if (item.kind == RecentKind.files && pc) _Do.reveal,
          _Do.remove,
        ];
    }
  }

  static (IconData, String) _label(_Do what) => switch (what) {
    _Do.copy => (Icons.content_copy_rounded, 'Copy'),
    _Do.openLink || _Do.open => (Icons.open_in_new_rounded, 'Open'),
    _Do.openFolder => (Icons.folder_open_outlined, 'Open folder'),
    _Do.reveal => (Icons.drive_file_move_outline, 'Show in folder'),
    _Do.share => (Icons.share_outlined, 'Share'),
    _Do.cancel => (Icons.close_rounded, 'Cancel'),
    _Do.remove => (Icons.delete_outline_rounded, 'Remove'),
  };

  Future<void> _openMenu(RecentEntry entry, List<_Do> menu, Offset? at) async {
    final colors = GotitColors.of(context);
    final _Do? picked;
    if (widget.isPc && at != null) {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      picked = await showMenu<_Do>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(at.dx, at.dy, 0, 0),
          Offset.zero & overlay.size,
        ),
        items: [
          for (final what in menu) ...[
            if (what == _Do.remove && menu.length > 1) const PopupMenuDivider(),
            PopupMenuItem(
              value: what,
              height: 40,
              child: Row(
                children: [
                  Icon(_label(what).$1, size: 18, color: colors.muted),
                  const SizedBox(width: 12),
                  Text(_label(what).$2),
                ],
              ),
            ),
          ],
        ],
      );
    } else {
      picked = await showModalBottomSheet<_Do>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _heading(entry),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final what in menu)
                  ListTile(
                    leading: Icon(_label(what).$1, color: colors.muted),
                    title: Text(_label(what).$2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GotitRadius.card),
                    ),
                    onTap: () => Navigator.of(context).pop(what),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (picked != null && mounted) _run(picked, entry);
  }

  static String _heading(RecentEntry entry) => switch (entry) {
    TransferEntry(:final transfer) => transfer.name,
    ItemEntry(:final item) when item.sensitive => hiddenText,
    ItemEntry(:final item) => switch (item.kind) {
      RecentKind.text || RecentKind.link => item.text.trim(),
      RecentKind.image => item.screenshot ? 'Screenshot' : 'Image',
      RecentKind.files => item.files.map((f) => f.name).join(', '),
    },
  };

  void _run(_Do what, RecentEntry entry) {
    if (entry is TransferEntry) {
      if (what == _Do.cancel) widget.transfers?.cancel(entry.transfer.id);
      return;
    }
    final item = (entry as ItemEntry).item;
    final actions = widget.actions;
    switch (what) {
      case _Do.copy:
        unawaited(_copy(item));
      case _Do.openLink:
        actions.openLink(item.text);
      case _Do.open:
        actions.open(item);
      case _Do.openFolder:
        actions.openFolder(item);
      case _Do.reveal:
        actions.reveal(item);
      case _Do.share:
        actions.share(item);
      case _Do.remove:
        final gone = widget.list.remove(item.id);
        if (gone != null) {
          _say('Removed', undo: () => widget.list.restore([gone]));
        }
      case _Do.cancel:
        break;
    }
  }

  Future<void> _copy(RecentItem item) async {
    final copied = await widget.actions.copy(item);
    if (!mounted) return;
    if (!copied) {
      _say("Couldn't copy it");
      return;
    }
    _copiedTimer?.cancel();
    setState(() => _copied = item.id);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  void _clear() {
    final gone = widget.list.clear();
    if (gone.isNotEmpty) {
      _say('Cleared', undo: () => widget.list.restore(gone));
    }
  }

  void _say(String message, {VoidCallback? undo}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          // With an action it would stay until tapped; Undo only works while
          // the list still holds what went.
          persist: false,
          action: undo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: undo),
        ),
      );
  }

  // --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final text = Theme.of(context).textTheme;
    final paired = widget.settings.value.peer != null;
    if (!paired && _shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Recent'.toUpperCase(), style: text.labelSmall),
                ),
                if (widget.list.value.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.muted,
                      minimumSize: const Size(48, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _clear,
                    child: const Text('Clear'),
                  )
                else
                  const SizedBox(height: 36),
              ],
            ),
          ),
          Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GotitRadius.card),
              side: BorderSide(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedList(
                  key: _listKey,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  initialItemCount: _shown.length,
                  itemBuilder: (context, index, animation) =>
                      _appear(animation, _row(_shown[index], index)),
                ),
                if (_shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Text(
                      'Nothing yet',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
