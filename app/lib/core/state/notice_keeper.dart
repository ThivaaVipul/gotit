import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/phone_setup.dart';
import 'package:gotit/core/sharing/sharing.dart';

/// Keeps the phone's ongoing notification in step with the link: there while
/// paired, saying how the link stands, "Sent to" the PC for a while after a
/// copy crossed, when MIUI has stopped the copy watcher, and "Sharing off"
/// with Turn on while the switch is off. It changes quietly, with no sound.
class NoticeKeeper {
  NoticeKeeper({
    required this.states,
    required this.current,
    required this.notice,
    this.watcher,
    this.sharing,
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
  final Duration sentFor;

  StreamSubscription<PhoneLinkState>? _listening;
  StreamSubscription<WatcherState>? _watching;
  WatcherState? _watcher;
  Timer? _sentTimer;
  bool _sentRecently = false;
  (String, String?, bool)? _shown;

  void start() {
    _listening = states.listen(_update);
    _watching = watcher?.listen((state) {
      _watcher = state;
      _update(current());
    });
    sharing?.addListener(_sharingChanged);
    _update(current());
  }

  Future<void> stop() async {
    await _listening?.cancel();
    await _watching?.cancel();
    sharing?.removeListener(_sharingChanged);
    _sentTimer?.cancel();
  }

  void _sharingChanged() => _update(current());

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
    final next = (title, text, on);
    if (next == _shown) return;
    _shown = next;
    unawaited(notice.show(title, text: text, sharing: on));
  }
}
