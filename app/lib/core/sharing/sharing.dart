import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

/// The shared sharing switch: on or off, when it last changed, and on which
/// device. Both devices keep one, and the later change wins.
@immutable
class SharingState {
  const SharingState({required this.on, required this.changedAt, this.by = ''});

  /// Sharing on, as it is until anyone changes it.
  static final initial = SharingState(
    on: true,
    changedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  final bool on;
  final DateTime changedAt;

  /// The ID of the device where it was changed.
  final String by;

  /// Whether this change came after [other]. Same moment: the higher device
  /// ID wins, so both sides pick the same one.
  bool isLaterThan(SharingState other) {
    if (changedAt.isAfter(other.changedAt)) return true;
    if (changedAt.isBefore(other.changedAt)) return false;
    return by.compareTo(other.by) > 0;
  }

  Map<String, Object?> toJson() => {
    'on': on,
    'at': changedAt.millisecondsSinceEpoch,
    'by': by,
  };

  static SharingState? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final on = json['on'];
    final at = json['at'];
    if (on is! bool || at is! int) return null;
    final by = json['by'];
    return SharingState(
      on: on,
      changedAt: DateTime.fromMillisecondsSinceEpoch(at),
      by: by is String ? by : '',
    );
  }

  Frame toFrame() => Frame(Frames.sharing, toJson());

  /// The state in [frame], or null when it isn't a whole one.
  static SharingState? fromFrame(Frame frame) =>
      frame.type == Frames.sharing ? fromJson(frame.fields) : null;

  @override
  bool operator ==(Object other) =>
      other is SharingState &&
      other.on == on &&
      other.changedAt == changedAt &&
      other.by == by;

  @override
  int get hashCode => Object.hash(on, changedAt, by);
}

/// The link, as far as the switch is concerned.
abstract interface class SharingLink {
  /// Sends the switch to the other device. False when it isn't reachable.
  bool sendSharing(SharingState state);

  /// The other device's switch, as it sends it.
  Stream<SharingState> get sharingChanges;

  /// Whether the other device is linked right now, and when that changes.
  bool get linked;
  Stream<bool> get linkedChanges;
}

/// This device's side of the shared switch. Flipping it here sends the change
/// to the other device; a later change from there replaces this one. Each
/// time the two link up, both send what they have, so a change made while
/// apart reaches the other side.
class SharingSwitch extends ValueNotifier<SharingState> {
  SharingSwitch({
    required SharingState initial,
    required this.deviceId,
    required this.link,
    required this.save,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(initial);

  /// This device's ID, recorded with each change made here.
  final String deviceId;
  final SharingLink link;

  /// Keeps the switch across restarts.
  final Future<void> Function(SharingState state) save;
  final DateTime Function() _clock;

  final _subscriptions = <StreamSubscription<Object?>>[];

  bool get on => value.on;

  void start() {
    _subscriptions
      ..add(link.sharingChanges.listen(_received))
      ..add(
        link.linkedChanges.listen((linked) {
          if (linked) link.sendSharing(value);
        }),
      );
    if (link.linked) link.sendSharing(value);
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  /// Turns sharing on or off for both devices.
  void set({required bool on}) {
    if (on == value.on) return;
    final next = SharingState(on: on, changedAt: _clock(), by: deviceId);
    _apply(next);
    link.sendSharing(next);
  }

  void _received(SharingState theirs) {
    if (theirs.isLaterThan(value)) _apply(theirs);
  }

  void _apply(SharingState next) {
    value = next;
    unawaited(save(next));
  }
}
