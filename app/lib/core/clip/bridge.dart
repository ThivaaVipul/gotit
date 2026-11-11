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

  /// Puts a clip from the other device on this one's clipboard.
  Future<void> write(Clip clip);
}

/// Carries copies between this device's clipboard and the link: copies made
/// here cross to the other device, and what arrives goes on the clipboard.
/// Nothing is queued: a copy made while the other device is away is dropped.
class ClipBridge {
  ClipBridge({
    required this.link,
    required this.clipboard,
    ClipGuard? guard,
    this.onSent,
    this.onArrived,
  }) : guard = guard ?? ClipGuard();

  final ClipLink link;
  final DeviceClipboard clipboard;
  final ClipGuard guard;

  /// A copy made here reached the other device.
  final void Function(Clip clip)? onSent;

  /// A copy from the other device is now on this clipboard.
  final void Function(Clip clip)? onArrived;

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

  void _copied(Clip clip) {
    if (clip.text.isEmpty || clip.tooBig) return;
    // Send on purpose always sends; a watched copy goes through the guard.
    if (!clip.manual && !guard.shouldSend(clip.text)) return;
    if (link.sendClip(clip)) onSent?.call(clip);
  }

  Future<void> _arrived(Clip clip) async {
    guard.wrote(clip.text);
    await clipboard.write(clip);
    onArrived?.call(clip);
  }
}
