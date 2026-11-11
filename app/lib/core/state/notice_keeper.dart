import 'dart:async';

import 'package:gotit/core/link/phone_link.dart';
import 'package:gotit/core/platform/phone_setup.dart';

/// Keeps the phone's ongoing notification in step with the link: there while
/// paired, saying how the link stands, and "Sent to" the PC for a while after
/// a copy crossed. It changes quietly, with no sound.
class NoticeKeeper {
  NoticeKeeper({
    required this.states,
    required this.current,
    required this.notice,
    this.sentFor = const Duration(minutes: 1),
  });

  /// The phone link's state changes, and its state right now.
  final Stream<PhoneLinkState> states;
  final PhoneLinkState Function() current;
  final LinkNotice notice;
  final Duration sentFor;

  StreamSubscription<PhoneLinkState>? _listening;
  Timer? _sentTimer;
  bool _sentRecently = false;
  (String, String?)? _shown;

  void start() {
    _listening = states.listen(_update);
    _update(current());
  }

  Future<void> stop() async {
    await _listening?.cancel();
    _sentTimer?.cancel();
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
    final title = switch (state.connection) {
      Connection.online => 'Connected to ${pc.name}',
      Connection.mismatch => 'Update Gotit to share with ${pc.name}',
      _ => 'Looking for ${pc.name}',
    };
    final text = _sentRecently && state.connection == Connection.online
        ? 'Sent to ${pc.name}'
        : null;
    final next = (title, text);
    if (next == _shown) return;
    _shown = next;
    unawaited(notice.show(title, text: text));
  }
}
