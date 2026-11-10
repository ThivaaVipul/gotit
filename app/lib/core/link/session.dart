import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

/// One open connection, encrypted, carrying frames both ways.
///
/// It answers pings by itself, pings when idle, and closes when the other
/// side goes quiet for longer than [silenceLimit]. Read with [next].
class LinkSession {
  LinkSession(
    this._socket, {
    Duration pingEvery = LinkSpec.pingEvery,
    this.silenceLimit = LinkSpec.silenceLimit,
  }) : _lastHeard = DateTime.now() {
    _subscription = const FrameDecoder()
        .bind(_socket)
        .listen(
          _onFrame,
          onError: (Object _) => unawaited(close()),
          onDone: () => unawaited(close()),
          cancelOnError: true,
        );
    _ticker = Timer.periodic(pingEvery, (_) => _tick());
    // Write errors, such as the other side resetting the connection, surface
    // here. Reading already closes the session for them; this keeps them from
    // going unhandled.
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) {}));
  }

  final Socket _socket;
  final Duration silenceLimit;
  late final StreamSubscription<Frame> _subscription;
  late final Timer _ticker;
  final _inbox = Queue<Frame>();
  final _done = Completer<void>();
  Completer<Frame?>? _waiter;
  DateTime _lastHeard;
  bool _closed = false;

  bool get isOpen => !_closed;

  /// Completes when the session has closed, for any reason.
  Future<void> get done => _done.future;

  /// The next frame, or null once the session closes or [timeout] passes.
  Future<Frame?> next({Duration? timeout}) {
    if (_inbox.isNotEmpty) return Future.value(_inbox.removeFirst());
    if (_closed) return Future.value(null);
    final waiter = Completer<Frame?>();
    _waiter = waiter;
    if (timeout == null) return waiter.future;
    return waiter.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_waiter, waiter)) _waiter = null;
        return null;
      },
    );
  }

  /// Sends [frame]. A session that can't send any more closes.
  void send(Frame frame) {
    if (_closed) return;
    try {
      _socket.add(encodeFrame(frame));
    } on Object {
      unawaited(close());
    }
  }

  /// Sends what is queued, then closes.
  Future<void> finish() async {
    if (_closed) return;
    try {
      await _socket.flush().timeout(const Duration(seconds: 2));
    } on Object {
      // Closing anyway.
    }
    await close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ticker.cancel();
    _waiter?.complete(null);
    _waiter = null;
    _socket.destroy();
    await _subscription.cancel();
    if (!_done.isCompleted) _done.complete();
  }

  void _onFrame(Frame frame) {
    _lastHeard = DateTime.now();
    switch (frame.type) {
      case Frames.ping:
        send(const Frame(Frames.pong));
      case Frames.pong:
        break;
      default:
        final waiter = _waiter;
        if (waiter != null) {
          _waiter = null;
          waiter.complete(frame);
        } else {
          _inbox.add(frame);
        }
    }
  }

  void _tick() {
    if (DateTime.now().difference(_lastHeard) > silenceLimit) {
      unawaited(close());
    } else {
      send(const Frame(Frames.ping));
    }
  }
}
