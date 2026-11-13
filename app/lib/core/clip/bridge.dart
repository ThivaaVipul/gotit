import 'dart:async';

import 'package:gotit/core/clip/clip.dart';

/// The link, as far as copies are concerned.
abstract interface class ClipLink {
  /// Sends [clip] to the other device. False when it isn't reachable.
  bool sendClip(Clip clip);

  /// Clips arriving from the other device.
  Stream<Clip> get clips;
}

/// This device's clipboard.
abstract interface class DeviceClipboard {
  /// Copies made on this device.
  Stream<Clip> get copies;

  /// Puts [clip] on this device's clipboard (one from the other device, or
  /// one copied again from the recent list), marked as Gotit's own so it
  /// isn't reported as a new copy. Gives back a mark for [wipe], or null
  /// when this clipboard can't be wiped later.
  Future<Object?> write(Clip clip);

  /// Clears the clipboard, but only while it still holds what the write
  /// that gave [mark] put there.
  Future<void> wipe(Object mark);
}

/// Carries copies between this device's clipboard and the link: copies made
/// here cross to the other device, and what arrives goes on the clipboard.
/// Nothing is queued: a copy made while the other device is away, or while
/// sharing is off, is dropped.
class ClipBridge {
  ClipBridge({
    required this.link,
    required this.clipboard,
    ClipGuard? guard,
    bool Function()? sharing,
    this.onSent,
    this.onArrived,
  }) : guard = guard ?? ClipGuard(),
       sharing = sharing ?? _always;

  final ClipLink link;
  final DeviceClipboard clipboard;
  final ClipGuard guard;

  /// Whether the sharing switch is on: nothing crosses either way while off.
  final bool Function() sharing;

  static bool _always() => true;

  /// A copy made here reached the other device.
  final void Function(Clip clip)? onSent;

  /// A copy from the other device is now on this clipboard; [mark] is what
  /// the clipboard gave back for wiping it later.
  final void Function(Clip clip, Object? mark)? onArrived;

  final _subscriptions = <StreamSubscription<Clip>>[];

  void start() {
    _subscriptions
      ..add(clipboard.copies.listen(_copied))
      ..add(link.clips.listen((clip) => unawaited(_arrived(clip))));
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  /// Sends [clip] now, past the guard (it was sent on purpose): true when
  /// it went.
  bool sendNow(Clip clip) {
    if (!sharing() || clip.isEmpty || clip.tooBig) return false;
    final sent = link.sendClip(clip);
    if (sent) onSent?.call(clip);
    return sent;
  }

  /// Puts [clip] back on this device's clipboard only: it doesn't cross.
  /// Gives back the clipboard's mark for wiping it later.
  Future<Object?> copyHere(Clip clip) {
    guard.wrote(clip.key);
    return clipboard.write(clip);
  }

  void _copied(Clip clip) {
    if (!sharing() || clip.isEmpty || clip.tooBig) return;
    // Send on purpose always sends; a watched copy goes through the guard.
    if (!clip.manual && !guard.shouldSend(clip.key)) return;
    if (link.sendClip(clip)) onSent?.call(clip);
  }

  Future<void> _arrived(Clip clip) async {
    if (!sharing() || clip.tooBig) return;
    guard.wrote(clip.key);
    final mark = await clipboard.write(clip);
    onArrived?.call(clip, mark);
  }
}
