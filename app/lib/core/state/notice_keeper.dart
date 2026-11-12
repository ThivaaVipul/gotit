import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/sharing/sharing.dart';
import 'package:gotit/core/transfer/transfers.dart';

/// Keeps the phone's ongoing notification in step with the link: there while
/// paired, saying how the link stands, "Sent to" the PC for a while after a
/// copy crossed, when MIUI has stopped the copy watcher, and "Sharing off"
/// with Turn on while the switch is off. A file on its way, either way, takes
/// it over with its progress and Cancel. It changes quietly, with no sound.
class NoticeKeeper {
  NoticeKeeper({
    required this.states,
    required this.current,
    required this.notice,
    this.watcher,
    this.sharing,
    this.transfers,
    this.sentFor = const Duration(minutes: 1),
  });

  /// The phone link's state changes, and its state right now.
  final Stream<PhoneLinkState> states;
  final PhoneLinkState Function() current;
  final LinkNotice notice;

  /// The copy watcher starting and stopping.
  final Stream<WatcherState>? watcher;

  /// The sharing switch.
  final ValueListenable<SharingState>? sharing;

  /// Files on their way: one being sent or received shows its progress and
  /// Cancel.
  final ValueListenable<List<Transfer>>? transfers;
  final Duration sentFor;

  StreamSubscription<PhoneLinkState>? _listening;
  StreamSubscription<WatcherState>? _watching;
  WatcherState? _watcher;
  Timer? _sentTimer;
  bool _sentRecently = false;
  (String, String?, bool, int?, String?)? _shown;
  final _wasSending = <String>{};

  void start() {
    _listening = states.listen(_update);
    _watching = watcher?.listen((state) {
      _watcher = state;
      _update(current());
    });
    sharing?.addListener(_sharingChanged);
    transfers?.addListener(_transfersChanged);
    _update(current());
  }

  Future<void> stop() async {
    await _listening?.cancel();
    await _watching?.cancel();
    sharing?.removeListener(_sharingChanged);
    transfers?.removeListener(_transfersChanged);
    _sentTimer?.cancel();
  }

  void _sharingChanged() => _update(current());

  void _transfersChanged() {
    // A file that just finished sending gets the same quiet sign as a copy.
    for (final transfer in transfers?.value ?? const <Transfer>[]) {
      if (transfer.direction != TransferDirection.sending) continue;
      if (transfer.running) {
        _wasSending.add(transfer.id);
      } else if (_wasSending.remove(transfer.id) &&
          transfer.status == TransferStatus.done) {
        sent();
        return;
      }
    }
    _update(current());
  }

  /// A copy from this phone reached the PC.
  void sent() {
    _sentRecently = true;
    _sentTimer?.cancel();
    _sentTimer = Timer(sentFor, () {
      _sentRecently = false;
      _update(current());
    });
    _update(current());
  }

  void _update(PhoneLinkState state) {
    final pc = state.pc;
    if (pc == null) {
      if (_shown != null) {
        _shown = null;
        unawaited(notice.hide());
      }
      return;
    }
    final link = switch (state.connection) {
      Connection.online => 'Connected to ${pc.name}',
      Connection.mismatch => 'Update Gotit to share with ${pc.name}',
      _ => 'Looking for ${pc.name}',
    };
    final on = sharing?.value.on ?? true;
    // While off: what the switch says, then how the link stands, so it's
    // clear the PC can still turn sharing back on.
    final title = on ? link : 'Sharing off';
    final text = !on
        ? link
        : _sentRecently && state.connection == Connection.online
        ? 'Sent to ${pc.name}'
        : switch (_watcher) {
            WatcherState.stopped => 'Copy watching stopped',
            WatcherState.turnedOff => 'Copy watching is off',
            _ => null,
          };
    // A file on its way, either way, takes the notification over: its name,
    // its progress, and Cancel.
    Transfer? moving;
    for (final transfer in transfers?.value ?? const <Transfer>[]) {
      if (transfer.running) moving = transfer;
    }
    if (moving != null && state.connection == Connection.online) {
      final percent = moving.progress == null
          ? null
          : (moving.progress! * 100).round();
      final next = (
        moving.direction == TransferDirection.sending
            ? 'Sending to ${pc.name}'
            : 'Receiving from ${pc.name}',
        moving.name,
        on,
        percent,
        moving.id,
      );
      if (next == _shown) return;
      _shown = next;
      unawaited(
        notice.show(
          next.$1,
          text: next.$2,
          sharing: on,
          percent: percent,
          cancel: moving.id,
        ),
      );
      return;
    }
    final next = (title, text, on, null, null);
    if (next == _shown) return;
    _shown = next;
    unawaited(notice.show(title, text: text, sharing: on));
  }
}
