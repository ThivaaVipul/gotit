import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:gotit/core/link/frame.dart';
import 'package:gotit/core/link/protocol.dart';

/// One open connection, encrypted, carrying frames both ways.
///
/// It answers pings by itself, pings when idle, and closes when the other
/// side goes quiet for longer than [silenceLimit]. Read with [next].
///
/// Big transfers stay small in memory both ways: [sendAndWait] waits for a
/// frame to leave before the next is read from disk, and reading pauses while
/// more than [backlog] frames wait to be handled, so TCP slows the sender.
class LinkSession {
  LinkSession(
    this._socket, {
    Duration pingEvery = LinkSpec.pingEvery,
    this.silenceLimit = LinkSpec.silenceLimit,
    this.backlog = 32,
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

  /// Frames waiting to be handled before reading pauses.
  final int backlog;
  late final StreamSubscription<Frame> _subscription;
  late final Timer _ticker;
  final _inbox = Queue<Frame>();
  final _outbox = Queue<Uint8List>();
  final _done = Completer<void>();

  /// A flush is under way: the socket takes nothing else until it ends, so
  /// frames queue in [_outbox] meanwhile.
  bool _flushing = false;
  Future<void> _lastWait = Future.value();
  Completer<Frame?>? _waiter;
  DateTime _lastHeard;
  bool _closed = false;

  bool get isOpen => !_closed;

  /// Completes when the session has closed, for any reason.
  Future<void> get done => _done.future;

  /// The next frame, or null once the session closes or [timeout] passes.
  Future<Frame?> next({Duration? timeout}) {
    if (_inbox.isNotEmpty) {
      final frame = _inbox.removeFirst();
      // Caught up: read again.
      if (_subscription.isPaused && _inbox.length <= backlog ~/ 4) {
        _subscription.resume();
      }
      return Future.value(frame);
    }
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
    _outbox.add(encodeFrame(frame));
    if (!_flushing) _write();
  }

  /// Sends [frame] and waits until it has left for the network, so a big
  /// file is read no faster than it can go. False once the session closed.
  /// Calls wait their turn.
  Future<bool> sendAndWait(Frame frame) {
    final turn = _lastWait.then((_) => _sendAndWait(frame));
    _lastWait = turn.then((_) {}, onError: (Object _) {});
    return turn;
  }

  Future<bool> _sendAndWait(Frame frame) async {
    if (_closed) return false;
    _outbox.add(encodeFrame(frame));
    _write();
    if (_closed) return false;
    _flushing = true;
    try {
      await _socket.flush();
    } on Object {
      unawaited(close());
      return false;
    } finally {
      _flushing = false;
    }
    // Anything sent while the flush was under way.
    _write();
    return !_closed;
  }

  void _write() {
    try {
      while (_outbox.isNotEmpty) {
        _socket.add(_outbox.removeFirst());
      }
    } on Object {
      unawaited(close());
    }
  }

  /// Sends what is queued, then closes.
  Future<void> finish() async {
    if (_closed) return;
    try {
      await _lastWait.timeout(const Duration(seconds: 2));
      _write();
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
          // Handling has fallen behind (a slow disk): stop reading, so the
          // other side's sending slows down instead of filling memory here.
          if (_inbox.length >= backlog && !_subscription.isPaused) {
            _subscription.pause();
          }
        }
    }
  }

  void _tick() {
    // Paused reading hears nothing, but frames are waiting: not silence.
    if (_subscription.isPaused) _lastHeard = DateTime.now();
    if (DateTime.now().difference(_lastHeard) > silenceLimit) {
      unawaited(close());
    } else {
      send(const Frame(Frames.ping));
    }
  }
}
