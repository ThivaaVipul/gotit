import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';
import 'package:gotit/core/sharing/sharing.dart';

class FakeLink implements SharingLink {
  bool up = false;
  final sent = <SharingState>[];
  // Closed in tearDown.
  // ignore: close_sinks
  final incoming = StreamController<SharingState>.broadcast();
  // ignore: close_sinks
  final ups = StreamController<bool>.broadcast();

  @override
  bool sendSharing(SharingState state) {
    if (!up) return false;
    sent.add(state);
    return true;
  }

  @override
  Stream<SharingState> get sharingChanges => incoming.stream;

  @override
  bool get linked => up;

  @override
  Stream<bool> get linkedChanges => ups.stream;
}

SharingState _state(bool on, int minute, String by) =>
    SharingState(on: on, changedAt: DateTime(2026, 11, 11, 9, minute), by: by);

void main() {
  group('the state', () {
    test('a later change wins, and a tie goes by device ID', () {
      expect(_state(false, 2, 'a').isLaterThan(_state(true, 1, 'b')), isTrue);
      expect(_state(true, 1, 'b').isLaterThan(_state(false, 2, 'a')), isFalse);
      expect(_state(false, 1, 'b').isLaterThan(_state(true, 1, 'a')), isTrue);
      expect(_state(true, 1, 'a').isLaterThan(_state(false, 1, 'b')), isFalse);
    });

    test('keeps as JSON and crosses as a frame', () {
      final state = _state(false, 5, 'phone');
      expect(SharingState.fromJson(state.toJson()), state);
      expect(SharingState.fromFrame(state.toFrame()), state);
      expect(SharingState.fromJson({'on': 'yes'}), isNull);
      expect(SharingState.fromFrame(const Frame(Frames.clip)), isNull);
    });

    test('starts on', () => expect(SharingState.initial.on, isTrue));
  });

  group('the switch', () {
    late FakeLink link;
    late List<SharingState> saved;
    late SharingSwitch sharing;
    final now = DateTime(2026, 11, 11, 10);

    setUp(() {
      link = FakeLink();
      saved = [];
      sharing = SharingSwitch(
        initial: SharingState.initial,
        deviceId: 'here',
        link: link,
        save: (state) async => saved.add(state),
        clock: () => now,
      )..start();
    });

    tearDown(() async {
      await sharing.stop();
      await link.incoming.close();
      await link.ups.close();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('flipping it here keeps it and tells the other device', () {
      link.up = true;
      sharing.set(on: false);
      expect(sharing.on, isFalse);
      expect(saved.single, _stateAt(false, now, 'here'));
      expect(link.sent.single.on, isFalse);
      // Flipping it to what it already is changes nothing.
      sharing.set(on: false);
      expect(link.sent, hasLength(1));
    });

    test('a later change from the other device replaces this one', () async {
      link.incoming.add(_stateAt(false, now, 'there'));
      await settle();
      expect(sharing.on, isFalse);
      expect(saved.single.by, 'there');
    });

    test('an older change from the other device is ignored', () async {
      sharing.set(on: false);
      link.incoming.add(
        _stateAt(true, now.subtract(const Duration(minutes: 5)), 'there'),
      );
      await settle();
      expect(sharing.on, isFalse);
    });

    test('a change made while apart reaches the other device', () async {
      sharing.set(on: false);
      expect(link.sent, isEmpty);
      link.up = true;
      link.ups.add(true);
      await settle();
      expect(link.sent.single.on, isFalse);
    });
  });
}

SharingState _stateAt(bool on, DateTime at, String by) =>
    SharingState(on: on, changedAt: at, by: by);
